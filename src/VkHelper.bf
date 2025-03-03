#pragma warning disable 4204

using System;
using System.Collections;
using System.Diagnostics;

using Glfw;
using Vulkan;

namespace Runestone;

static
{
	public static T VkQueryFunc<T>(VkInstance instance) where T : operator explicit void*
	{
		[Comptime(ConstEval=true)]
		StringView GetFuncName()
		{
			let type = typeof(T);
			if (type.IsGenericParam) return null;
			let name = type.GetName(..scope .());
			Runtime.Assert(name.StartsWith("PFN_"));
			return name..Remove(0, 4)..EnsureNullTerminator();
		}
		return (.)(void*)vkGetInstanceProcAddr(instance, GetFuncName().Ptr);
	}

	public static mixin VkTry(VkResult result)
	{
		if (result != .VK_SUCCESS)
			return .Err(result);
	}
}

enum PhysicalDeviceFeatures
{
	[Comptime, OnCompile(.TypeInit)]
	static void TypeInit()
	{
		String emit = scope .();
		String from = scope .(), to = scope .();
		let type = typeof(VkPhysicalDeviceFeatures);
		int value = 1;
		int shift = 0;
		for (let field in type.GetFields())
		{
			let originalName = field.GetSourceName(..scope .());
			String newName = scope .(originalName);
			newName[0] = newName[0].ToUpper;
			emit.AppendF($"case {newName} = {value};\n");
			from.AppendF($"result |= (.)(vk.{originalName} << (VkBool32){shift});\n\t");
			to.AppendF($"{originalName} = (.)(self & .{newName}),\n\t\t");
			value <<= 1;
			shift++;
		}
		Compiler.EmitTypeBody(typeof(Self), scope $$"""
			{{emit}}

			public static explicit operator Self(VkPhysicalDeviceFeatures vk)
			{
				Self result = default;
				{{from}}

				return result;
			}

			public static explicit operator VkPhysicalDeviceFeatures(Self self)
			{
				return .()
				{
					{{to}}

				};
			}
			""");
	}
}

enum Beefify<T> : int32
{
	[Comptime, OnCompile(.TypeInit)]
	static void TypeInit()
	{
		String emit = scope .();
		let type = typeof(T);

		StringView typeName = type.GetName(..scope .());
		if (typeName.EndsWith("KHR") || typeName.EndsWith("EXT"))
			typeName.RemoveFromEnd(3);
		if (typeName.EndsWith("FlagBits"))
			typeName.RemoveFromEnd(8);
		String prefix = scope .();
		for (let char in typeName)
		{
			if (char.IsUpper) prefix.Append('_');
			prefix.Append(char.ToUpper);
		}
		prefix.Remove(0);

		for (let field in type.GetFields())
		{
			if (!field.IsEnumCase) continue;
			StringView fieldName = field.GetSourceName(..scope .());
			if (!fieldName.StartsWith(prefix)) continue;
			fieldName.RemoveFromStart(prefix.Length);
			if (fieldName.EndsWith("_KHR") || fieldName.EndsWith("_EXT"))
				fieldName.RemoveFromEnd(4);
			if (fieldName.EndsWith("_BIT"))
				fieldName.RemoveFromEnd(4);
			else if (fieldName.StartsWith("_MAX_ENUM")) continue;
			String newName = scope .();
			for (let char in fieldName)
				if (char == '_')
					newName.Append(@char.GetNext());
				else
					newName.Append(char.ToLower);
			if (newName[0].IsDigit)
				newName.Insert(0, '_');
			emit.AppendF($"case {newName} = {field.[Friend]mFieldData.mData};\n");
		}

		Compiler.EmitTypeBody(typeof(Self), emit);
	}
}

interface IRunestoneAllocator
{
	public VkAllocationCallbacks* VkAlloc { get; }
	public GLFWallocator* GlfwAlloc { get; }
}

class CRTBumpAllocator : BumpAllocator, IRunestoneAllocator
{
	protected override Span<uint8> AllocPool()
	{
		int poolSize = (this.[Friend]mPools != null) ? this.[Friend]mPools.Count : 0;
		int allocSize = Math.Clamp((int)Math.Pow(poolSize, 1.5) * PoolSizeMin, PoolSizeMin, PoolSizeMax);
		return Span<uint8>(new:gCRTAlloc uint8[allocSize]* (?), allocSize);
	}

	protected override void FreePool(Span<uint8> span)
	{
		delete:gCRTAlloc span.Ptr;
	}

	protected override void* AllocLarge(int size, int align)
	{
		return new:gCRTAlloc uint8[size]* (?);
	}

	protected override void FreeLarge(void* ptr)
	{
		delete:gCRTAlloc ptr;
	}

	HashSet<void*> realloced;
	public void* Realloc(void* original, int newSize, int align)
	{
		if (realloced == null)
			realloced = new .();
		else if (realloced.Contains(original))
			delete:gCRTAlloc original;
		defer { realloced.Add(@return); }
		return new:gCRTAlloc uint8[newSize]* (?);
	}

	public ~this()
	{
		DeleteContainerAndItems!(realloced);
	}

	VkAllocationCallbacks mVkAlloc = .()
	{
		pUserData = &this,
		pfnAllocation = (userData, size, align, allocScope) => (*(Self*)userData).Alloc((.)size, (.)align),
		pfnReallocation = (userData, original, size, align, allocScope) => (*(Self*)userData).Realloc(original, (.)size, (.)align),
		pfnFree = (userData, ptr) => { /* Does nothing */ },
	};

	GLFWallocator mGlfwAlloc = .()
	{
		user = &this,
		allocate = (size, userData) => (*(Self*)userData).Alloc((.)size, 1),
		reallocate = (original, size, userData) => (*(Self*)userData).Realloc(original, (.)size, 1),
		deallocate = (ptr, userData) => { /* Does nothing */ },
	};

	public VkAllocationCallbacks* VkAlloc => &mVkAlloc;
	public GLFWallocator* GlfwAlloc => &mGlfwAlloc;
}

namespace Vulkan;

extension VkResult
{
	[Warn("VkResult discarded"), SkipCall]
	public void ReturnValueDiscarded();
}

namespace System;

extension CRTAlloc : Runestone.IRunestoneAllocator
{
	[CLink]
	public static extern void* realloc(void* ptr, uint newSize);

	static VkAllocationCallbacks sVkAlloc = .()
	{
		pfnAllocation = (userData, size, align, allocScope) => (*(Self*)userData).Alloc((.)size, (.)align),
		pfnReallocation = (userData, original, size, align, allocScope) => realloc(original, size),
		pfnFree = (userData, ptr) => Internal.StdFree(ptr),
	};

	static GLFWallocator sGlfwAlloc = .()
	{
		allocate = (size, userData) => Internal.StdMalloc((.)size),
		reallocate = (original, size, userData) => realloc(original, size),
		deallocate = (ptr, userData) => Internal.StdFree(ptr),
	};

	public VkAllocationCallbacks* VkAlloc => &sVkAlloc;
	public GLFWallocator* GlfwAlloc => &sGlfwAlloc;
}
