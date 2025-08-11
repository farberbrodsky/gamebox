The current command is:

```sh
zig build --cache-dir zig-cache && VK_ADD_IMPLICIT_LAYER_PATH=$PWD/src/VkLayer_gamebox_persist.json vkcube --validate --c 1
```

```sh
cd triangle
zig build --cache-dir ../zig-cache && VK_ADD_IMPLICIT_LAYER_PATH=$PWD/../src/VkLayer_gamebox_persist.json ./triangle_vertex
```

```sh
zig build build-generator && ./zig-out/bin/generate_vk_wrappers Vulkan-Headers/registry/vk.xml /tmp/vk_wrappers.zig
```
