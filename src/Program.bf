using System;
using System.Collections;
using System.Diagnostics;

using Glfw;
using Vulkan;

namespace Runestone;

class Program
{
	static int errorCount = 0;

	struct QueueFamilyIndices
	{
		public uint32? graphicsFamily, presentFamily;
		public bool IsComplete => graphicsFamily.HasValue && presentFamily.HasValue;
	}

	struct SwapChainDetails
	{
		public VkSurfaceCapabilitiesKHR capabilities;
		public VkSurfaceFormatKHR[] formats;
		public VkPresentModeKHR[] presentModes;
	}

	public static int Main(String[] args)
	{
		mixin VkCheck(VkResult result)
		{
			Runtime.Assert(result == .VK_SUCCESS);
		}

		defer
		{
			if (errorCount != 0)
				Internal.FatalError(scope $"{errorCount} validation errors occurred");
		}

		glfwInit();
		defer glfwTerminate();

		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);

		const uint32 windowWidth = 1400;
		const uint32 windowHeight = 800;
		let window = glfwCreateWindow(windowWidth, windowHeight, "Hello World", null, null);
		defer glfwDestroyWindow(window);

#if DEBUG
		char8*[] validationLayers = scope .("VK_LAYER_KHRONOS_validation");
		{
			VkCheck!(vkEnumerateInstanceLayerProperties(var layerCount, null));
			VkLayerProperties[] layerProperties = scope .[layerCount];
			VkCheck!(vkEnumerateInstanceLayerProperties(out layerCount, layerProperties.Ptr));
			check: for (let layer in validationLayers)
			{
				for (var properties in layerProperties)
					if (StringView(layer) == StringView(&properties.layerName))
						continue check;
				Runtime.FatalError(scope $"Missing validation layer: {StringView(layer)}");
			}
		}

		VkDebugUtilsMessengerCreateInfoEXT debugMessengerCreateInfo = .()
		{
			sType = .VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity =
				.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
				.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
				.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
			messageType =
				.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
				.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
				.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
			pfnUserCallback = => DebugLogCallback,
		};
#endif

		let glfwExtensions = glfwGetRequiredInstanceExtensions(let glfwExtensionCount);
		List<char8*> instanceExtensions = scope .(.(glfwExtensions, glfwExtensionCount));
		instanceExtensions.Add(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

		Runtime.Assert(vkCreateInstance(scope .()
		{
			sType = .VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
			pApplicationInfo = scope .()
			{
				sType = .VK_STRUCTURE_TYPE_APPLICATION_INFO,
				pApplicationName = "Hello World",
				applicationVersion = VK_MAKE_API_VERSION(0, 0, 1, 0),
				pEngineName = "Runestone Framework",
				engineVersion = VK_MAKE_API_VERSION(0, 0, 1, 0),
				apiVersion = VK_API_VERSION_1_3,
			},
			enabledExtensionCount = (.)instanceExtensions.Count,
			ppEnabledExtensionNames = instanceExtensions.Ptr,
#if DEBUG
			enabledLayerCount = (.)validationLayers.Count,
			ppEnabledLayerNames = validationLayers.Ptr,
			pNext = &debugMessengerCreateInfo,
#endif
		}, null, let instance) == .VK_SUCCESS);
		defer vkDestroyInstance(instance, null);

#if DEBUG
		[CallingConvention(VKAPI_CALL)]
		static VkBool32 DebugLogCallback(VkDebugUtilsMessageSeverityFlagBitsEXT severity, VkDebugUtilsMessageTypeFlagsEXT, VkDebugUtilsMessengerCallbackDataEXT* message, void*)
		{
			switch (severity)
			{
			case .VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT:
			case .VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT:
				errorCount++;
			default:
				return false;
			}

			Debug.WriteLine(StringView(message.pMessage));
			Console.Write(StringView(message.pMessage));
			Console.Write("\n\n");

			return false;
		}

		VkDebugUtilsMessengerEXT debugMessenger = null;
		Runtime.Assert(VkQueryFunc<PFN_vkCreateDebugUtilsMessengerEXT>(instance).Invoke(instance, &debugMessengerCreateInfo, null, &debugMessenger) == .VK_SUCCESS);
		defer VkQueryFunc<PFN_vkDestroyDebugUtilsMessengerEXT>(instance).Invoke(instance, debugMessenger, null);
#endif

		Runtime.Assert(glfwCreateWindowSurface(instance, window, null, let surface) == .VK_SUCCESS);
		defer vkDestroySurfaceKHR(instance, surface, null);

		VkSurfaceFormatKHR optimalFormat = .() { format = .VK_FORMAT_B8G8R8A8_SRGB, colorSpace = .VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
		VkPresentModeKHR optimalPresentMode = .VK_PRESENT_MODE_MAILBOX_KHR;

		char8*[] deviceExtensions = scope .(VK_KHR_SWAPCHAIN_EXTENSION_NAME);
		VkPhysicalDevice physicalDevice = null;
		QueueFamilyIndices queueFamilyIndices = .();
		VkPhysicalDeviceFeatures physicalFeatures = ?;
		SwapChainDetails swapDetails = ?;
		{
			VkCheck!(vkEnumeratePhysicalDevices(instance, var deviceCount, null));
			Runtime.Assert(deviceCount > 0, "No GPUs found that support Vulkan");
			VkPhysicalDevice[] devices = scope .[deviceCount];
			VkCheck!(vkEnumeratePhysicalDevices(instance, out deviceCount, devices.Ptr));
			int currentScore = -1;
			findDevice: for (let option in devices)
			{
				vkGetPhysicalDeviceProperties(option, let properties);
				vkGetPhysicalDeviceFeatures(option, let features);
				if (!features.geometryShader) continue;

				QueueFamilyIndices indices = .();
				vkGetPhysicalDeviceQueueFamilyProperties(option, var propertyCount, null);
				VkQueueFamilyProperties[] propertiesArr = scope .[propertyCount];
				vkGetPhysicalDeviceQueueFamilyProperties(option, out propertyCount, propertiesArr.Ptr);
				for (let familyProperties in propertiesArr)
				{
					uint32 i = (.)@familyProperties;
					if (familyProperties.queueFlags & .VK_QUEUE_FLAG_BITS_MAX_ENUM != 0)
						indices.graphicsFamily = i;
					Runtime.Assert(vkGetPhysicalDeviceSurfaceSupportKHR(option, i, surface, let pSupported) == .VK_SUCCESS);
					if (pSupported) indices.presentFamily = i;
					if (indices.IsComplete) break;
				}
				if (!indices.IsComplete) continue;

				VkCheck!(vkEnumerateDeviceExtensionProperties(option, null, var extensionCount, null));
				VkExtensionProperties[] avaliableExtensions = scope .[extensionCount];
				VkCheck!(vkEnumerateDeviceExtensionProperties(option, null, out extensionCount, avaliableExtensions.Ptr));
				check: for (var deviceExtension in deviceExtensions)
				{
					for (var extProperties in avaliableExtensions)
						if (StringView(deviceExtension) == StringView(&extProperties.extensionName))
							continue check;
					continue findDevice;
				}

				SwapChainDetails details = .();
				VkCheck!(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(option, surface, out details.capabilities));
				VkCheck!(vkGetPhysicalDeviceSurfaceFormatsKHR(option, surface, var formatCount, null));
			    details.formats = scope .[formatCount];
			    VkCheck!(vkGetPhysicalDeviceSurfaceFormatsKHR(option, surface, out formatCount, details.formats.Ptr));
				VkCheck!(vkGetPhysicalDeviceSurfacePresentModesKHR(option, surface, var presentModeCount, null));
			    details.presentModes = scope .[presentModeCount];
			    VkCheck!(vkGetPhysicalDeviceSurfacePresentModesKHR(option, surface, out presentModeCount, details.presentModes.Ptr));
				if (details.formats.IsEmpty || details.presentModes.IsEmpty) continue;

				int score = 0;
				if (properties.deviceType == .VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU)
					score += 1000;
				score += properties.limits.maxImageDimension2D;
				if (score < currentScore) continue;
				currentScore = score;
				physicalDevice = option;
				queueFamilyIndices = indices;
				physicalFeatures = features;
				swapDetails = details;
			}
		}
		Runtime.Assert(physicalDevice != null, "Your GPU is not suitable for rendering");


		HashSet<uint32> uniqueFamilyIndices = scope .() { queueFamilyIndices.graphicsFamily.Value, queueFamilyIndices.presentFamily.Value };
		List<VkDeviceQueueCreateInfo> queueCreateInfos = scope .(uniqueFamilyIndices.Count);
		float queuePriority = 1.f;
		for (let familyIndex in uniqueFamilyIndices)
			queueCreateInfos.Add(.()
			{
				sType = .VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
				queueFamilyIndex = familyIndex,
				queueCount = 1,
				pQueuePriorities = &queuePriority,
			});
		Runtime.Assert(vkCreateDevice(physicalDevice, scope .()
		{
			sType = .VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
			pEnabledFeatures = &physicalFeatures,
			pQueueCreateInfos = queueCreateInfos.Ptr,
			queueCreateInfoCount = (.)queueCreateInfos.Count,

			enabledLayerCount = 0,
			ppEnabledExtensionNames = deviceExtensions.Ptr,
			enabledExtensionCount = (.)deviceExtensions.Count,
		}, null, let device) == .VK_SUCCESS);
		defer vkDestroyDevice(device, null);
		vkGetDeviceQueue(device, queueFamilyIndices.graphicsFamily.Value, 0, let graphicsQueue);
		vkGetDeviceQueue(device, queueFamilyIndices.presentFamily.Value, 0, let presentQueue);

		VkSurfaceFormatKHR surfaceFormat = ?;
		VkPresentModeKHR presentMode = ?;
		VkExtent2D swapChainExtent = ?;
		{
			if (swapDetails.formats.Contains(optimalFormat))
				surfaceFormat = optimalFormat;
			else
				surfaceFormat = swapDetails.formats[0];
			if (swapDetails.presentModes.Contains(optimalPresentMode))
				presentMode = optimalPresentMode;
			else
				presentMode = .VK_PRESENT_MODE_FIFO_KHR;
			if (swapDetails.capabilities.currentExtent.width != uint32.MaxValue)
			    swapChainExtent = swapDetails.capabilities.currentExtent;
			else
			{
			    glfwGetFramebufferSize(window, let width, let height);
			    swapChainExtent = .() { width = (.)width, height = (.)height };
			    swapChainExtent.width = Math.Clamp(swapChainExtent.width, swapDetails.capabilities.minImageExtent.width, swapDetails.capabilities.maxImageExtent.width);
			    swapChainExtent.height = Math.Clamp(swapChainExtent.height, swapDetails.capabilities.minImageExtent.height, swapDetails.capabilities.maxImageExtent.height);
			}
		}

		uint32 swapImageCount = swapDetails.capabilities.minImageCount + 1;
		if (swapDetails.capabilities.maxImageCount > 0 && swapImageCount > swapDetails.capabilities.maxImageCount)
		    swapImageCount = swapDetails.capabilities.maxImageCount;
		VkSwapchainCreateInfoKHR swapchainCreateInfo = .()
		{
			sType = .VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
			surface = surface,
			minImageCount = swapImageCount,
			imageFormat = surfaceFormat.format,
			imageColorSpace = surfaceFormat.colorSpace,
			imageExtent = swapChainExtent,
			imageArrayLayers = 1,
			imageUsage = .VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,

			preTransform = swapDetails.capabilities.currentTransform,
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
		Runtime.Assert(vkCreateSwapchainKHR(device, &swapchainCreateInfo, null, var swapchain) == .VK_SUCCESS);
		defer vkDestroySwapchainKHR(device, swapchain, null);

		VkImageView[] swapImageViews;
		{
			VkCheck!(vkGetSwapchainImagesKHR(device, swapchain, var imageCount, null));
			swapImageViews = scope:: .[imageCount];
			VkImage[] swapImages = scope:: .[imageCount];
			VkCheck!(vkGetSwapchainImagesKHR(device, swapchain, out imageCount, swapImages.Ptr));
			for (let i < swapImageCount)
			{
				Runtime.Assert(vkCreateImageView(device, scope .()
				{
					sType = .VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
					image = swapImages[i],
					viewType = .VK_IMAGE_VIEW_TYPE_2D,
					format = surfaceFormat.format,
					components = .()
					{
						r = .VK_COMPONENT_SWIZZLE_IDENTITY,
						g = .VK_COMPONENT_SWIZZLE_IDENTITY,
						b = .VK_COMPONENT_SWIZZLE_IDENTITY,
						a = .VK_COMPONENT_SWIZZLE_IDENTITY,
					},
					subresourceRange = .()
					{
						aspectMask = .VK_IMAGE_ASPECT_COLOR_BIT,
						baseMipLevel = 0,
						levelCount = 1,
						baseArrayLayer = 0,
						layerCount = 1,
					},
				}, null, out swapImageViews[i]) == .VK_SUCCESS);
				defer:: vkDestroyImageView(device, swapImageViews[i], null);
			}
		}

		List<VkPipelineShaderStageCreateInfo> shaderStages = scope .(2);
		VkShaderModule CreateShaderModule(Span<uint8> code, VkShaderStageFlags stage)
		{
			Runtime.Assert(vkCreateShaderModule(device, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
				codeSize = (.)code.Length,
				pCode = (.)code.Ptr,
			}, null, let module) == .VK_SUCCESS);
			shaderStages.Add(.()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
				stage = stage,
				module = module,
				pName = "main",
			});
			return module;
		}
		let vertexShader = CreateShaderModule(Compiler.ReadBinary("src/Shader/vert.spv"), .VK_SHADER_STAGE_VERTEX_BIT);
		let fragmentShader = CreateShaderModule(Compiler.ReadBinary("src/Shader/frag.spv"), .VK_SHADER_STAGE_FRAGMENT_BIT);
		defer vkDestroyShaderModule(device, vertexShader, null);
		defer vkDestroyShaderModule(device, fragmentShader, null);

		VkPipeline pipeline;
		VkPipelineLayout pipelineLayout;
		VkRenderPass renderPass;
		{
			VkDynamicState[] dynamicStates = scope .(.VK_DYNAMIC_STATE_VIEWPORT, .VK_DYNAMIC_STATE_SCISSOR);
			VkPipelineDynamicStateCreateInfo dynamicState = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
				dynamicStateCount = (.)dynamicStates.Count,
				pDynamicStates = dynamicStates.Ptr,
			};
			VkPipelineVertexInputStateCreateInfo vertexInputInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
				vertexBindingDescriptionCount = 0,
				vertexAttributeDescriptionCount = 0,
			};
			VkPipelineInputAssemblyStateCreateInfo inputAssembly = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
				topology = .VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
				primitiveRestartEnable = false,
			};
			VkPipelineViewportStateCreateInfo viewportState = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
				viewportCount = 1,
				pViewports = scope .()
				{
					x = 0, y = 0,
					width = windowWidth,
					height = windowHeight,
					minDepth = 0.f,
					maxDepth = 1.f,
				},
				scissorCount = 1,
				pScissors = scope .()
				{
					offset = default,
					extent = swapChainExtent,
				},
			};
			VkPipelineRasterizationStateCreateInfo rasterizer = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
				depthClampEnable = false,
				rasterizerDiscardEnable = false,
				polygonMode = .VK_POLYGON_MODE_FILL,
				lineWidth = 1.f,
				cullMode = .VK_CULL_MODE_BACK_BIT,
				frontFace = .VK_FRONT_FACE_CLOCKWISE,
				depthBiasEnable = false,
			};
			VkPipelineMultisampleStateCreateInfo multisampling = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
				sampleShadingEnable = false,
				rasterizationSamples = .VK_SAMPLE_COUNT_1_BIT,
				minSampleShading = 1.0f, // Optional
				pSampleMask = null, // Optional
				alphaToCoverageEnable = false, // Optional
				alphaToOneEnable = false, // Optional
			};
			VkPipelineColorBlendAttachmentState colorBlendAttachment = .()
			{
				colorWriteMask =
					.VK_COLOR_COMPONENT_R_BIT |
					.VK_COLOR_COMPONENT_G_BIT |
					.VK_COLOR_COMPONENT_B_BIT |
					.VK_COLOR_COMPONENT_A_BIT,
				blendEnable = true,
				srcColorBlendFactor = .VK_BLEND_FACTOR_SRC_ALPHA,
				dstColorBlendFactor = .VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
				colorBlendOp = .VK_BLEND_OP_ADD,
				srcAlphaBlendFactor = .VK_BLEND_FACTOR_ONE,
				dstAlphaBlendFactor = .VK_BLEND_FACTOR_ZERO,
				alphaBlendOp = .VK_BLEND_OP_ADD,
			};
			VkPipelineColorBlendStateCreateInfo colorBlending = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
				logicOpEnable = false,
				logicOp = .VK_LOGIC_OP_COPY, // Optional
				attachmentCount = 1,
				pAttachments = &colorBlendAttachment,
			};
			Runtime.Assert(vkCreatePipelineLayout(device, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
				setLayoutCount = 0, // Optional
				pSetLayouts = null, // Optional
				pushConstantRangeCount = 0, // Optional
				pPushConstantRanges = null, // Optional
			}, null, out pipelineLayout) == .VK_SUCCESS);
			defer:: vkDestroyPipelineLayout(device, pipelineLayout, null);
			VkAttachmentDescription colorAttachment = .()
			{
				format = surfaceFormat.format,
				samples = .VK_SAMPLE_COUNT_1_BIT,
				loadOp = .VK_ATTACHMENT_LOAD_OP_CLEAR,
				storeOp = .VK_ATTACHMENT_STORE_OP_STORE,
				stencilLoadOp = .VK_ATTACHMENT_LOAD_OP_DONT_CARE,
				stencilStoreOp = .VK_ATTACHMENT_STORE_OP_DONT_CARE,
				initialLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
				finalLayout = .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
			};
			VkSubpassDescription subpass = .()
			{
				pipelineBindPoint = .VK_PIPELINE_BIND_POINT_GRAPHICS,
				colorAttachmentCount = 1,
				pColorAttachments = scope .()
				{
					attachment = 0,
					layout = .VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
				}
			};
			Runtime.Assert(vkCreateRenderPass(device, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
				attachmentCount = 1,
				pAttachments = &colorAttachment,
				subpassCount = 1,
				pSubpasses = &subpass,
				dependencyCount = 1,
				pDependencies = scope .()
				{
					srcSubpass = VK_SUBPASS_EXTERNAL,
					dstSubpass = 0,
					srcStageMask = .VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
					dstStageMask = .VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
					srcAccessMask = 0,
					dstAccessMask = .VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
				}
			}, null, out renderPass) == .VK_SUCCESS);
			defer:: vkDestroyRenderPass(device, renderPass, null);

			Runtime.Assert(vkCreateGraphicsPipelines(device, null, 1, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
				stageCount = (.)shaderStages.Count,
				pStages = shaderStages.Ptr,
				pVertexInputState = &vertexInputInfo,
				pInputAssemblyState = &inputAssembly,
				pViewportState = &viewportState,
				pRasterizationState = &rasterizer,
				pMultisampleState = &multisampling,
				pDepthStencilState = null, // Optional
				pColorBlendState = &colorBlending,
				pDynamicState = &dynamicState,
				layout = pipelineLayout,
				renderPass = renderPass,
				subpass = 0,
			}, null, out pipeline) == .VK_SUCCESS);
			defer:: vkDestroyPipeline(device, pipeline, null);
		}

		VkFramebuffer[] framebuffers = scope .[swapImageViews.Count];
		for (let i < framebuffers.Count)
		{
			Runtime.Assert(vkCreateFramebuffer(device, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
				renderPass = renderPass,
				attachmentCount = 1,
				pAttachments = &swapImageViews[i],
				width = swapChainExtent.width,
				height = swapChainExtent.height,
				layers = 1,
			}, null, out framebuffers[i]) == .VK_SUCCESS);
			defer:: vkDestroyFramebuffer(device, framebuffers[i], null);
		}

		Runtime.Assert(vkCreateCommandPool(device, scope .()
		{
			sType = .VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
			flags = .VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
			queueFamilyIndex = queueFamilyIndices.graphicsFamily.Value,
		}, null, let commandPool) == .VK_SUCCESS);
		defer vkDestroyCommandPool(device, commandPool, null);
		Runtime.Assert(vkAllocateCommandBuffers(device, scope .()
		{
			sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool = commandPool,
			level = .VK_COMMAND_BUFFER_LEVEL_PRIMARY,
			commandBufferCount = 1,
		}, var commandBuffer) == .VK_SUCCESS);
		defer vkFreeCommandBuffers(device, commandPool, 1, &commandBuffer);

		void RecordCommandBuffer(uint32 imageIndex)
		{
			Runtime.Assert(vkBeginCommandBuffer(commandBuffer, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
			}) == .VK_SUCCESS);
			vkCmdBeginRenderPass(commandBuffer, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
				renderPass = renderPass,
				framebuffer = framebuffers[imageIndex],
				renderArea = .() { extent = swapChainExtent },
				clearValueCount = 1,
				pClearValues = scope .()
				{
					color = .() { float32 = .(0.f, 0.f, 0.f, 1.f) },
					depthStencil = default,
				},
			}, .VK_SUBPASS_CONTENTS_INLINE);
			{
				vkCmdBindPipeline(commandBuffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

				VkViewport viewport = .();
				viewport.x = 0.0f;
				viewport.y = 0.0f;
				viewport.width = swapChainExtent.width;
				viewport.height = swapChainExtent.height;
				viewport.minDepth = 0.0f;
				viewport.maxDepth = 1.0f;
				vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

				VkRect2D scissor = .();
				scissor.offset = default;
				scissor.extent = swapChainExtent;
				vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

				vkCmdDraw(commandBuffer, 3, 1, 0, 0);
			}
			vkCmdEndRenderPass(commandBuffer);

			Runtime.Assert(vkEndCommandBuffer(commandBuffer) == .VK_SUCCESS, "Failed to record command buffer");
		}

		VkSemaphore imageAvailableSemaphore;
		VkSemaphore renderFinishedSemaphore;
		VkFence inFlightFence;
		{
			VkSemaphoreCreateInfo* semaphoreInfo = scope .()
			{
				sType = .VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
			};
			VkFenceCreateInfo* fenceInfo = scope .()
			{
				sType = .VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
				flags = .VK_FENCE_CREATE_SIGNALED_BIT,
			};
			Runtime.Assert(vkCreateSemaphore(device, semaphoreInfo, null, out imageAvailableSemaphore) == .VK_SUCCESS);
			Runtime.Assert(vkCreateSemaphore(device, semaphoreInfo, null, out renderFinishedSemaphore) == .VK_SUCCESS);
			Runtime.Assert(vkCreateFence(device, fenceInfo, null, out inFlightFence) == .VK_SUCCESS);
			defer:: vkDestroySemaphore(device, imageAvailableSemaphore, null);
			defer:: vkDestroySemaphore(device, renderFinishedSemaphore, null);
			defer:: vkDestroyFence(device, inFlightFence, null);
		}

		VkPipelineStageFlags waitStages = .VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		while (glfwWindowShouldClose(window) == GLFW_FALSE)
		{
			glfwPollEvents();
			VkCheck!(vkWaitForFences(device, 1, &inFlightFence, true, uint64.MaxValue));
			VkCheck!(vkResetFences(device, 1, &inFlightFence));
			VkCheck!(vkAcquireNextImageKHR(device, swapchain, uint64.MaxValue, imageAvailableSemaphore, null, var imageIndex));
			VkCheck!(vkResetCommandBuffer(commandBuffer, 0));
			RecordCommandBuffer(imageIndex);
			Runtime.Assert(vkQueueSubmit(graphicsQueue, 1, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
				waitSemaphoreCount = 1,
				pWaitSemaphores = &imageAvailableSemaphore,
				pWaitDstStageMask = (.)&waitStages,
				commandBufferCount = 1,
				pCommandBuffers = &commandBuffer,
				signalSemaphoreCount = 1,
				pSignalSemaphores = &renderFinishedSemaphore,
			}, inFlightFence) == .VK_SUCCESS);
			VkCheck!(vkQueuePresentKHR(graphicsQueue, scope .()
			{
				sType = .VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
				waitSemaphoreCount = 1,
				pWaitSemaphores = &renderFinishedSemaphore,
				swapchainCount = 1,
				pSwapchains = &swapchain,
				pImageIndices = &imageIndex,
			}));
		}

		VkCheck!(vkDeviceWaitIdle(device));
		return errorCount;
	}
}