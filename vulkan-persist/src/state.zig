const std = @import("std");
const vk = @import("vk_headers");
const wrappers = @import("vk_wrappers");

const AnyInstance = ?*opaque {};
const InstanceTableHeader = struct {
    const Self = @This();

    /// This entry is relevant only if the instance matches
    /// The real instance can't be null, but null can be used as a placeholder value if the first instance was destroyed.
    instance: AnyInstance = null,

    /// There is a next pointer if you need to look at the next state object. It is a lock-free (for readers) singly linked list.
    /// We are assuming that the common case is only a single Vulkan instance, but otherwise you need to traverse a linked list.
    next: std.atomic.Value(?*Self) = std.atomic.Value(?*Self).init(null),

    /// The allocator in here was used to allocate this entry, too! Except for the first one, which is optimized.
    /// It is nullable because some vulkan users pass a null VkAllocator
    allocator: ?*const vk.Allocator = undefined,

    pub fn alloc(self: *Self) std.mem.Allocator {
        return vk.Allocator.allocator(self.allocator);
    }
};

fn InstanceTable(comptime vk_type: type, comptime EntryStruct: type) type {
    return struct {
        const Entry = EntryStruct;
        const Self = @This();

        /// Writers need a lock, whereas readers are completely lock-free.
        lock: std.Thread.Mutex = .{},

        /// The head is special because it's not allocated by the instance's own allocator. It's optimized by sitting inline.
        /// If head's instance is null, then it can be reused.
        head: Entry = .{},

        /// Finds the entry for a given instance.
        pub fn find(self: *Self, instance: vk_type) ?*Entry {
            std.debug.assert(instance != null);
            var link: ?*InstanceTableHeader = &self.head.header;
            return while (link) |hdr| : (link = hdr.next.load(.acquire)) {
                if (hdr.instance == @as(AnyInstance, @ptrCast(instance)))
                    break @fieldParentPtr("header", hdr);
            } else null;
        }

        const Iterator = struct {
            position: ?*InstanceTableHeader,

            pub fn next(self: *Iterator) ?*Entry {
                if (self.position) |h| {
                    self.position = h.next.load(.acquire);
                    return @fieldParentPtr("header", h);
                } else {
                    return null;
                }
            }
        };

        pub fn iterate(self: *Self) Iterator {
            if (self.head.header.instance != null) {
                return .{ .position = &self.head.header };
            } else {
                return .{ .position = self.head.header.next.load(.acquire) };
            }
        }

        /// Creates a new entry, either from head or by using its allocator
        /// May fail to allocate, and then return null.
        pub fn append(self: *Self, instance: vk_type, allocator: ?*const vk.Allocator, entry_init: Entry.initializer) ?*Entry {
            std.debug.assert(instance != null);
            // writes happen under a lock
            self.lock.lock();
            defer self.lock.unlock();

            // Using the instance's allocator for the instance's entry
            const alloc = vk.Allocator.allocator(allocator);

            // Either take the head, or create a new entry
            const new_state = if (self.head.header.instance == null)
                &self.head
            else
                alloc.create(Entry) catch return null;

            // Put data into this entry
            // NOTE: If next is already non-null for the head, keep it that way!
            //       And if it's a new entry, then next is already set to null.
            new_state.header.instance = @as(AnyInstance, @ptrCast(instance));
            new_state.header.allocator = allocator;
            const init_result = new_state.init(entry_init);
            if (!init_result) {
                // failed to initialize. Destroy everything.
                if (&new_state.header != &self.head.header) {
                    alloc.destroy(new_state);
                } else {
                    new_state.header.instance = null;
                }
                return null;
            }

            // Store into the linked list, unless it's the head
            if (&new_state.header != &self.head.header) {
                var link = &self.head.header;

                // Advance until the end of the list
                while (true) {
                    const next = link.next.load(.unordered);
                    if (next) |l| {
                        link = l;
                    } else {
                        break;
                    }
                }

                link.next.store(&new_state.header, .release);
            }

            return new_state;
        }

        pub fn destroy(self: *Self, instance: vk_type) void {
            std.debug.assert(instance != null);
            // writes happen under a lock
            self.lock.lock();
            defer self.lock.unlock();

            if (self.head.header.instance == @as(AnyInstance, @ptrCast(instance))) {
                // The only solution is to assign null to instance. We can't free the object.
                self.head.header.instance = null;
                self.head.deinit();
                return;
            } else {
                // Find the state object before the one we are removing
                var link: ?*Entry = self.head;
                var next: ?*Entry = undefined;
                while (link) {
                    next = link.header.next.load(.unordered);
                    if (next.header.instance == @as(AnyInstance, @ptrCast(instance)))
                        break;
                    link = next;
                }

                if (link == null) {
                    // instance should be known to us
                    std.debug.panic("Instance being destroyed does not appear in any records\n", .{});
                    return;
                } else |prev| {
                    // Destroy and unlink the destroyed entry
                    const destroyed = next.?;
                    destroyed.deinit();
                    prev.header.next.store(destroyed.header.next.load(.unordered), .release);
                    // Destroy it with its own allocator
                    const alloc = destroyed.header.alloc();
                    alloc.destroy(destroyed);
                }
            }
        }
    };
}

pub const InstanceState = InstanceTable(vk.Instance, struct {
    const Self = @This();
    header: InstanceTableHeader = .{},

    // From the initializer:
    nextGetInstanceProcAddr: vk.c.PFN_vkGetInstanceProcAddr = undefined,

    // Automatically initialized:
    dispatch_table: wrappers.InstanceDispatchTable = undefined,
    phys_device_set: std.hash_map.AutoHashMapUnmanaged(vk.c.VkPhysicalDevice, void) = undefined,
    pfnCreateDevice: vk.c.PFN_vkCreateDevice = undefined,
    pfnEnumeratePhysicalDevices: vk.c.PFN_vkEnumeratePhysicalDevices = undefined,

    const initializer = struct { vk.c.PFN_vkGetInstanceProcAddr };
    pub fn init(self: *Self, i: initializer) bool {
        self.nextGetInstanceProcAddr = i[0];
        self.dispatch_table = .{};
        self.phys_device_set = @TypeOf(self.phys_device_set).empty;
        self.pfnCreateDevice = @ptrCast(self.get_proc_addr("vkCreateDevice") orelse return false);
        self.pfnEnumeratePhysicalDevices = @ptrCast(self.get_proc_addr("vkEnumeratePhysicalDevices") orelse return false);
        return true;
    }

    pub fn deinit(self: *Self) void {
        self.phys_device_set.deinit(self.header.allocator.allocator());
    }

    /// Can be called in init() but only after initializing nextGetInstanceProcAddr.
    fn get_proc_addr(self: *Self, fn_name: [*:0]const u8) ?vk.c.PFN_vkVoidFunction {
        return self.nextGetInstanceProcAddr.?(@ptrCast(self.header.instance), fn_name);
    }

    pub fn add_device(self: *Self, device: vk.c.VkPhysicalDevice) !void {
        std.debug.print("xyz: {any}\n", .{self.phys_device_set});
        try self.phys_device_set.put(self.header.alloc(), device, {});
    }

    pub fn has_device(self: *Self, device: vk.c.VkPhysicalDevice) bool {
        return self.phys_device_set.get(device) != null;
    }
});

pub const DeviceState = InstanceTable(vk.Device, struct {
    const Self = @This();
    header: InstanceTableHeader = .{},

    // From the initializer:
    parent_state: *InstanceState.Entry = undefined,
    pfnGetDeviceProcAddr: vk.c.PFN_vkGetDeviceProcAddr = undefined,

    // Automatically initialized:
    // ...

    const initializer = struct { *InstanceState.Entry, vk.c.PFN_vkGetDeviceProcAddr };
    pub fn init(self: *Self, i: initializer) bool {
        self.parent_state = i[0];
        self.pfnGetDeviceProcAddr = i[1];
        return true;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
});
