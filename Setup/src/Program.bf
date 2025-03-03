using System;
using System.IO;

namespace Setup;

static class Program
{
	[CLink] extern static int32 system(char8*);

	const let vulkanSdkVersionsDefaultPath =
#if BF_PLATFORM_WINDOWS
		@"C:\VulkanSDK\";
#else
		"/VulkanSDK/";
#endif

	public static int Main()
	{
		int result = 0;
		void RunCommand(char8* command)
		{
			Console.WriteLine($"> {StringView(command)}");
			//result += system(command);
			Console.WriteLine();
		}

		if (Directory.Exists("../deps/glfw/src/.git"))
			RunCommand("git -C ../deps/glfw/src fetch --depth 1");
		else
			RunCommand("git clone https://github.com/glfw/glfw.git ../deps/glfw/src --depth 1");

		if (result != 0) return result;

		bool IsVulkanSDK(StringView path)
			=> File.Exists(Path.Combine(..scope .(), path, "components.xml"));

		String vulkanSdkPath = scope .();
		do
		{
	 		if (Directory.Exists(vulkanSdkVersionsDefaultPath))
			{
				if (IsVulkanSDK(vulkanSdkVersionsDefaultPath))
				{
					vulkanSdkPath.Append(vulkanSdkVersionsDefaultPath);
					break;
				}

				DateTime createdTime = .MinValue;
				for (let dir in Directory.EnumerateDirectories(vulkanSdkVersionsDefaultPath))
				{
					if (!IsVulkanSDK(dir.GetFilePath(..scope .())))
						continue;

					let time = dir.GetCreatedTime();
					if (createdTime >= time) continue;
					createdTime = time;
					vulkanSdkPath.Clear();
					dir.GetFilePath(vulkanSdkPath);
				}

				if (!vulkanSdkPath.IsEmpty)
				{
					Console.WriteLine($"Vulkan Sdk path set to be {vulkanSdkPath}");
					break;
				}
			}

			Console.WriteLine("Unable to find LunarG Vulkan SDK! (https://vulkan.lunarg.com/)\neither you haven't installed it yet or have specified a custom install location");
			repeat
			{
				if (!vulkanSdkPath.IsEmpty)
				{
					Console.WriteLine($"{vulkanSdkPath} is not a vulkan sdk (TODO: linux)"); //!
					vulkanSdkPath.Clear();
				}
				Console.Write("Please enter the path to your vulkan sdk: ");
				Console.ReadLine(vulkanSdkPath);
			}
			while (!IsVulkanSDK(vulkanSdkPath));
			Console.WriteLine();
		}

		Runtime.Assert(IsVulkanSDK(vulkanSdkPath));
		File.WriteAllText("../deps/vulkan/sdk_path.txt", vulkanSdkPath);

		Bindings.args = scope char8*[]("--language=c", scope $"-I{vulkanSdkPath}/Include", "-I../deps/glfw/src/include", "-DGLFW_INCLUDE_VULKAN");
		Bindings.File("../deps/glfw/src/include/glfw/glfw3.h", "../deps/glfw/src/glfw.bf", .Glfw);
		Bindings.File(scope $"{vulkanSdkPath}/Include/vulkan/vulkan.h", "../deps/vulkan/src/vulkan.bf", .Vulkan);

		return result;
	}
}