{ den, ... }:
{
  # The permanent streaming aspect enables WSI. Apply this extra source fix
  # afterwards, while keeping its retirement independent from WSI itself.
  den.aspects.streaming.provides.to-hosts =
    { ... }:
    {
      nixos =
        { lib, ... }:
        {
          nixpkgs.overlays = lib.mkAfter [
            (_final: prev: {
              gamescope = prev.gamescope.overrideAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace subprojects/vkroots/vkroots.h --replace-fail \
                    'deviceDispatch->GetDeviceQueue(device, queueInfo.queueFamilyIndex, j, &queue);' \
                    'if (queueInfo.flags) { VkDeviceQueueInfo2 q2; q2.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2; q2.pNext = nullptr; q2.flags = queueInfo.flags; q2.queueFamilyIndex = queueInfo.queueFamilyIndex; q2.queueIndex = j; deviceDispatch->GetDeviceQueue2(device, &q2, &queue); } else deviceDispatch->GetDeviceQueue(device, queueInfo.queueFamilyIndex, j, &queue);'

                  substituteInPlace subprojects/vkroots/vkroots.h --replace-fail \
                    'deviceDispatch->GetDeviceQueue(device, queueInfo.queueFamilyIndex, i, &queue);' \
                    'if (queueInfo.flags) { VkDeviceQueueInfo2 q2; q2.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2; q2.pNext = nullptr; q2.flags = queueInfo.flags; q2.queueFamilyIndex = queueInfo.queueFamilyIndex; q2.queueIndex = i; deviceDispatch->GetDeviceQueue2(device, &q2, &queue); } else deviceDispatch->GetDeviceQueue(device, queueInfo.queueFamilyIndex, i, &queue);'
                '';
              });
            })
          ];
        };
    };
}
