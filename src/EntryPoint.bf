#pragma warning disable 4204

using System;
using System.IO;
using System.Collections;
using System.Diagnostics;

using Glfw;
using Vulkan;

namespace Runestone;

static class RunestoneVersion
{
	public const uint32 Major = 0, Minor = 1, Patch = 0;
	public const uint32 Version = VK_MAKE_API_VERSION(0, Major, Minor, Patch);
}

/** @brief add the the entry point, contains the Main method
 *
 *  Example code:
 *  ```bf
 *  static class Program : RunestoneApplication
 *  {
 *		public override Settings Settings = .()
 *		{
 *  		WindowName = "Runestone Application",
 *  		WindowDimensions = .Ratio(3, 2),
 *  		WindowFlags = .FullscreenIfRelease,
 *  		RenderSettings = .Preset2D,
 *  
 *  
 *		}
 *  }
 *  ```
 */
abstract class RunestoneApplication
{
	/** @brief allpurpose settings
	 *
	 *  Following options are mandatory
	 *  * WindowName
	 *  * WindowDimensions
	 *  * RenderSettings
	 */
	public struct Settings
	{
		public char8* WindowName;
		public enum
		{
			[NoShow(false)] case Unspecified;
			case Maximum;
			case Exact(uint32 width, uint32 heigth);
			case Ratio(uint32 widthParts, uint32 heigthParts);
		} WindowDimensions;
		public enum : int32
		{
			Fullscreen = 1,
			Resizeable = _<<1,
			Maximized = _<<1,
			FullscreenIfRelease = _<<1,
			CursorHidden = _<<1,
		} WindowFlags;

		/// when null, will use the WindowName
		public char8* ApplicationName = null;
		public uint32 ApplicationVersion = VK_MAKE_API_VERSION(0, 0, 1, 0);

		public struct
		{
			private bool specified = true;

			public bool PostProcessingSubpass = false;

			public VkFormat OptimalFormat = .VK_FORMAT_B8G8R8A8_SRGB;
			public Beefify<VkColorSpaceKHR> OptimalColorSpace = .SrgbNonlinear;
			public Beefify<VkPresentModeKHR> OptimalPresentMode = .Mailbox;
			public PhysicalDeviceFeatures RequiredFeatures;
		} RenderSettings;

		/// when true, will enable vulkan debug messenger
		/// see also DebugCallback
		public bool DebugFeatures =
#if DEBUG
			true;
#else
			false;
#endif
	}

	public abstract Settings Settings { get; }

	public CRTBumpAllocator alloc;
	internal GLFWwindow* glfwWindow;
	internal VkInstance vkInstance;
	internal VkDebugUtilsMessengerEXT vkDebugMessenger;
	internal VkSurfaceKHR khrSurface;

	internal VkDevice vkDevice;
	internal VkQueue graphicsQueue;
	internal VkQueue presentQueue;
	internal VkSwapchainKHR khrSwapchain;

	/// requires debug features.
	/// `message` is valid until function returns.
	protected virtual void OnMessageLog(enum { Error, Warning, Info } severity, StringView message, enum { Glfw, Vulkan, Runestone } source)
	{
		switch (severity)
		{
		case .Info: return;
		case .Error: Console.Error.WriteLine(message);
		case .Warning:
		}
		Debug.WriteLine($"[{source}] {message}");
	}

	protected virtual void GetInstanceExtensions(List<char8*> outList)
	{
		let glfwExtensions = glfwGetRequiredInstanceExtensions(let glfwExtensionCount);
		outList.AddRange(.(glfwExtensions, glfwExtensionCount));
		if (Settings.DebugFeatures)
			outList.Add(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
	}

	protected virtual void GetDeviceExtensions(List<char8*> outList)
	{
		outList.Add(VK_KHR_SWAPCHAIN_EXTENSION_NAME);
	}

	/// return <0 to indicate that the device is not suitable
	protected virtual int RatePhysicalDevice(in VkPhysicalDevice device, in VkPhysicalDeviceProperties properties)
	{
		int score = 0;
		if (properties.deviceType case .VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU)
			score += 1000;
		score += properties.limits.maxImageDimension2D;
		return score;
	}

	public Result<void, VkResult> RunApplication()
	{
		alloc = scope .();
		var settings = Settings;
		Debug.Assert(settings.WindowName != null, "Missing mandatory setting: WindowName");
		Debug.Assert(settings.WindowDimensions != .Unspecified, "Missing mandatory setting: WindowDimensions");
		Debug.Assert(settings.RenderSettings.[Friend]specified, "Missing mandatory setting: RenderSettings");
		
		{
			glfwInitAllocator(alloc.GlfwAlloc);
			if (glfwInit() == GLFW_FALSE)
			{
				char8* description = ?;
				glfwGetError(&description);
				OnMessageLog(.Error, .(description), .Glfw);
				return .Err(.VK_ERROR_UNKNOWN);
			}
			defer:: glfwTerminate();

			glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
			glfwWindowHint(GLFW_RESIZABLE, (.)(settings.WindowFlags & .Resizeable));
			glfwWindowHint(GLFW_MAXIMIZED, (.)(settings.WindowFlags & .Maximized));

			GLFWmonitor* monitor = null;
			if (settings.WindowFlags.HasFlag(.Fullscreen)
#if RELEASE
				|| settings.WindowFlags.HasFlag(.FullscreenIfRelease)
#endif
			) monitor = glfwGetPrimaryMonitor();

			glfwWindow = glfwCreateWindow(500, 500, settings.WindowName, monitor, null);
			defer:: glfwDestroyWindow(glfwWindow);

			if (settings.WindowFlags.HasFlag(.CursorHidden))
				glfwSetInputMode(glfwWindow, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
		}

		VkDebugUtilsMessengerCreateInfoEXT* debugMessengerCreateInfo = null;
		char8*[] validationLayers;
		if (settings.DebugFeatures)
		{
			validationLayers = scope:: .("VK_LAYER_KHRONOS_validation");
			VkTry!(vkEnumerateInstanceLayerProperties(var layerCount, null));
			VkLayerProperties[] supportedLayers = scope .[layerCount];
			VkTry!(vkEnumerateInstanceLayerProperties(out layerCount, supportedLayers.Ptr));
			check: for (let layer in validationLayers)
			{
				StringView layerStr = .(layer);
				for (var properties in supportedLayers)
					if (StringView(&properties.layerName) == layerStr)
						continue check;
				OnMessageLog(.Error, scope $"Validation layer: {layerStr} not supported", .Runestone);
				return .Err(.VK_ERROR_UNKNOWN);
			}

			debugMessengerCreateInfo = scope:: .()
			{
				sType = .VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
				messageSeverity =
					.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT |
					.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
					.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT |
					.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
				messageType =
					.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
					.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
					.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
				pUserData = &this,
				pfnUserCallback = (severity, msgType, message, userData) =>
				{
					(*(Self*)userData).OnMessageLog(
						severity.HasFlag(.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) ? .Warning :
						severity.HasFlag(.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) ? .Error : .Info,
						.(message.pMessage), .Vulkan
					);
					return VK_FALSE;
				},
			};
		}
		else validationLayers = scope:: .();

		{
			let instanceExtensions = GetInstanceExtensions(..scope .());
			let result = vkCreateInstance(scope .()
			{
				sType = .VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
				pNext = debugMessengerCreateInfo,
				pApplicationInfo = scope .()
				{
					sType = .VK_STRUCTURE_TYPE_APPLICATION_INFO,
					pApplicationName = settings.ApplicationName == null ? settings.WindowName : settings.ApplicationName,
					applicationVersion = settings.ApplicationVersion,
					pEngineName = "Runestone Framework",
					engineVersion = RunestoneVersion.Version,
					apiVersion = VK_VERSION_1_0,
				},
				enabledExtensionCount = (.)instanceExtensions.Count,
				ppEnabledExtensionNames = instanceExtensions.Ptr,
				enabledLayerCount = (.)validationLayers.Count,
				ppEnabledLayerNames = validationLayers.Ptr,
			}, alloc.VkAlloc, out vkInstance);
			if (result != .VK_SUCCESS)
			{
				OnMessageLog(.Error, "Vulkan not supported", .Runestone);
				return .Err(result);
			}
			defer:: vkDestroyInstance(vkInstance, alloc.VkAlloc);
		}

		if (settings.DebugFeatures)
		{
			VkTry!(VkQueryFunc<PFN_vkCreateDebugUtilsMessengerEXT>(vkInstance).Invoke(vkInstance, scope .(), alloc.VkAlloc, &vkDebugMessenger));
			defer:: VkQueryFunc<PFN_vkDestroyDebugUtilsMessengerEXT>(vkInstance).Invoke(vkInstance, vkDebugMessenger, alloc.VkAlloc);
		}

		VkTry!(glfwCreateWindowSurface(vkInstance, glfwWindow, alloc.VkAlloc, out khrSurface));
		defer vkDestroySurfaceKHR(vkInstance, khrSurface, alloc.VkAlloc);

		struct
		{
			public uint32? graphicsFamily;
			public uint32? presentFamily;
			public bool IsComplete => graphicsFamily.HasValue && presentFamily.HasValue;
		} queueFamilyIndices = ?;
		struct
		{
			public VkSurfaceCapabilitiesKHR capabilities;
			public VkSurfaceFormatKHR[] formats;
			public VkPresentModeKHR[] presentModes;
		} swapChainDetails = ?;
		{
			let deviceExtensions = GetDeviceExtensions(..scope .());

			VkTry!(vkEnumeratePhysicalDevices(vkInstance, var physicalDeviceCount, null));
			VkPhysicalDevice[] physicalDevices = scope .[physicalDeviceCount];
			VkTry!(vkEnumeratePhysicalDevices(vkInstance, out physicalDeviceCount, physicalDevices.Ptr));
			
			int currentScore = -1;
			VkPhysicalDevice currentPhysicalDevice = null;
			findDevice: for (let physicalDevice in physicalDevices)
			{
				vkGetPhysicalDeviceProperties(physicalDevice, let properties);
				vkGetPhysicalDeviceFeatures(physicalDevice, let features);
				if (!((PhysicalDeviceFeatures)features).HasFlag(settings.RenderSettings.RequiredFeatures))
					continue;

				decltype(queueFamilyIndices) indices = .();
				vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, var propertyCount, null);
				VkQueueFamilyProperties[] propertiesArr = scope .[propertyCount];
				vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, out propertyCount, propertiesArr.Ptr);
				for (let familyProperties in propertiesArr)
				{
					uint32 i = (.)@familyProperties;
					if (familyProperties.queueFlags.HasFlag(.VK_QUEUE_FLAG_BITS_MAX_ENUM))
						indices.graphicsFamily = i;
					Runtime.Assert(vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, i, khrSurface, let pSupported) == .VK_SUCCESS);
					if (pSupported) indices.presentFamily = i;
					if (indices.IsComplete) break;
				}
				if (!indices.IsComplete) continue;

				VkTry!(vkEnumerateDeviceExtensionProperties(physicalDevice, null, var extensionCount, null));
				VkExtensionProperties[] avaliableExtensions = scope .[extensionCount];
				VkTry!(vkEnumerateDeviceExtensionProperties(physicalDevice, null, out extensionCount, avaliableExtensions.Ptr));
				check: for (var deviceExtension in deviceExtensions)
				{
					for (var extProperties in avaliableExtensions)
						if (StringView(deviceExtension) == StringView(&extProperties.extensionName))
							continue check;
					continue findDevice;
				}

				decltype(swapChainDetails) details = .();
				VkTry!(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, khrSurface, out details.capabilities));
				VkTry!(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, khrSurface, var formatCount, null));
				details.formats = scope .[formatCount];
				VkTry!(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, khrSurface, out formatCount, details.formats.Ptr));
				VkTry!(vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, khrSurface, var presentModeCount, null));
				details.presentModes = scope .[presentModeCount];
				VkTry!(vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, khrSurface, out presentModeCount, details.presentModes.Ptr));
				if (details.formats.IsEmpty || details.presentModes.IsEmpty) continue;

				int score = RatePhysicalDevice(physicalDevice, properties);
				if (currentScore >= score) continue;
				currentScore = score;
				currentPhysicalDevice = physicalDevice;
				queueFamilyIndices = indices;
				swapChainDetails = details;
			}

			if (currentPhysicalDevice == null)
			{
				OnMessageLog(.Error, "No GPU is suitable for rendering", .Runestone);
				return .Err(.VK_ERROR_UNKNOWN);
			}

			HashSet<uint32> uniqueQueueFamilyIndices = scope .() { queueFamilyIndices.graphicsFamily.Value,
																   queueFamilyIndices.presentFamily.Value };
			VkDeviceQueueCreateInfo[] queueCreateInfos = scope .[uniqueQueueFamilyIndices.Count];
			int i = 0;
			float queuePriority = 1.f;
			for (let index in uniqueQueueFamilyIndices)
				queueCreateInfos[++i] = .()
				{
					sType = .VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
					queueFamilyIndex = index,
					queueCount = 1,
					pQueuePriorities = &queuePriority,
				};

			VkPhysicalDeviceFeatures features = (.)settings.RenderSettings.RequiredFeatures;
			VkTry!(vkCreateDevice(currentPhysicalDevice, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
				queueCreateInfoCount = (.)queueCreateInfos.Count,
				pQueueCreateInfos = queueCreateInfos.Ptr,
				enabledLayerCount = 0,
				enabledExtensionCount = (.)deviceExtensions.Count,
				ppEnabledExtensionNames = deviceExtensions.Ptr,
				pEnabledFeatures = &features,
			}, alloc.VkAlloc, out vkDevice));
			defer:: vkDestroyDevice(vkDevice, alloc.VkAlloc);

			vkGetDeviceQueue(vkDevice, queueFamilyIndices.graphicsFamily.Value, 0, out graphicsQueue);
			vkGetDeviceQueue(vkDevice, queueFamilyIndices.presentFamily.Value, 0, out presentQueue);
		}

		VkSurfaceFormatKHR surfaceFormat = ?;
		VkPresentModeKHR presentMode = ?;
		VkExtent2D swapChainExtent = ?;
		{
			VkSurfaceFormatKHR optimalFormat = .()
			{
				format = settings.RenderSettings.OptimalFormat,
				colorSpace = (.)settings.RenderSettings.OptimalColorSpace,
			};
			if (swapChainDetails.formats.Contains(optimalFormat))
				surfaceFormat = optimalFormat;
			else
				surfaceFormat = swapChainDetails.formats[0];
			if (swapChainDetails.presentModes.Contains((.)settings.RenderSettings.OptimalPresentMode))
				presentMode = (.)settings.RenderSettings.OptimalPresentMode;
			else
				presentMode = .VK_PRESENT_MODE_FIFO_KHR;
			if (swapChainDetails.capabilities.currentExtent.width != uint32.MaxValue)
			    swapChainExtent = swapChainDetails.capabilities.currentExtent;
			else
			{
			    glfwGetFramebufferSize(glfwWindow, let width, let height);
			    swapChainExtent = .() { width = (.)width, height = (.)height };
			    swapChainExtent.width = Math.Clamp(swapChainExtent.width, swapChainDetails.capabilities.minImageExtent.width, swapChainDetails.capabilities.maxImageExtent.width);
			    swapChainExtent.height = Math.Clamp(swapChainExtent.height, swapChainDetails.capabilities.minImageExtent.height, swapChainDetails.capabilities.maxImageExtent.height);
			}

			uint32 swapImageCount = swapChainDetails.capabilities.minImageCount + 1;
			if (swapChainDetails.capabilities.maxImageCount > 0 && swapImageCount > swapChainDetails.capabilities.maxImageCount)
			    swapImageCount = swapChainDetails.capabilities.maxImageCount;
			VkSwapchainCreateInfoKHR swapchainCreateInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
				surface = khrSurface,
				minImageCount = swapImageCount,
				imageFormat = surfaceFormat.format,
				imageColorSpace = surfaceFormat.colorSpace,
				imageExtent = swapChainExtent,
				imageArrayLayers = 1,
				imageUsage = .VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,

				preTransform = swapChainDetails.capabilities.currentTransform,
				compositeAlpha = .VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
				presentMode = presentMode,
				clipped = true,
				oldSwapchain = null,
			};
			if (queueFamilyIndices.graphicsFamily != queueFamilyIndices.presentFamily)
			{
			    swapchainCreateInfo.imageSharingMode = .VK_SHARING_MODE_CONCURRENT;
			    swapchainCreateInfo.queueFamilyIndexCount = 2;
			    swapchainCreateInfo.pQueueFamilyIndices = scope:: uint32[](
					queueFamilyIndices.graphicsFamily.Value,
					queueFamilyIndices.presentFamily.Value,
				).Ptr;
			}
			else
			{
			    swapchainCreateInfo.imageSharingMode = .VK_SHARING_MODE_EXCLUSIVE;
			    swapchainCreateInfo.queueFamilyIndexCount = 0;
			    swapchainCreateInfo.pQueueFamilyIndices = null;
			}

			VkTry!(vkCreateSwapchainKHR(vkDevice, &swapchainCreateInfo, alloc.VkAlloc, out khrSwapchain));
			defer:: vkDestroySwapchainKHR(vkDevice, khrSwapchain, alloc.VkAlloc);
		}



		return .Ok;
	}
}
