using System;
using System.IO;
using System.Collections;
using System.Diagnostics;

using Vulkan;
using internal Runestone.RunestoneApplication;

namespace Runestone.Resources;

static
{
	internal const StringView vulkanSdkPath = Compiler.ReadText("deps/vulkan/sdk_path.txt");
	internal static int RunVkBinCommand(StringView command, StringView args)
	{
		String cmd = Path.Combine(..scope .(), vulkanSdkPath, "Bin", command);
#if BF_PLATFORM_WINDOWS 
		cmd.Append(".exe");
#endif
		SpawnedProcess proc = scope .();
		proc.Start(scope ProcessStartInfo()
			{
				CreateNoWindow = true,
				ErrorDialog = true,
			}
			..SetFileName(cmd)
			..SetArguments(args)
			..SetWorkingDirectory(Directory.GetCurrentDirectory(..scope .()))
		);
		proc.WaitFor();
		return proc.ExitCode;
	}
}

class Shader
{
	/** @brief compiles a shader at build time
	 *
	 *  Compiles a shader using `slangc`.
	 *  Supports following languages:
	 *   * glsl
	 *   * hlsl
	 *   * slang
	 */
	[Comptime]
	public static Span<uint8> Compile(StringView path)
	{
		if (!Compiler.IsBuilding) return null;
		Debug.WriteLine($"Compiling shader {path}");
		if (RunVkBinCommand("slangc", scope $"{path} -o {path}.spv") != 0)
			Internal.FatalError(scope $"Failed to compile shader: {path}");
		return File.ReadAll(scope $"{path}.spv", ..scope .());
	}

	protected RunestoneApplication mApp;
	protected IRunestoneAllocator mAlloc;
	public VkShaderModule vkHandle;

	public this(RunestoneApplication app, out VkResult result, Span<uint8> spv, char8* entryPoint = "main", IRunestoneAllocator alloc = CRTAlloc())
	{
		Debug.Assert(app.vkDevice != null);
		mApp = app;
		mAlloc = alloc;
		result = vkCreateShaderModule(app.vkDevice, scope .()
		{
			sType = .VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
			codeSize = (.)spv.Length,
			pCode = (.)spv.Ptr,
		}, alloc.VkAlloc, out vkHandle);
	}

	public ~this()
	{
		vkDestroyShaderModule(mApp.vkDevice, vkHandle, mAlloc.VkAlloc);
	}
}
