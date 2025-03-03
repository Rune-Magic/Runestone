using System;
using System.Numerics;
using System.Numerics.X86;
using System.Diagnostics;

using Runestone;
using internal Runestone.Collision;

namespace Runestone.Collision;

internal struct _2D;
internal struct _3D;
internal struct _4D;

internal struct _AABB<Dim, Tcorlib, TRunestone, Tbool>
	where Tcorlib : operator implicit TRunestone,
					operator Tcorlib + Tcorlib,
					operator Tcorlib - Tcorlib
	where TRunestone :	operator implicit Tcorlib
	where Tbool :	operator Tcorlib >= Tcorlib,
					operator Tcorlib <= Tcorlib,
					operator Tbool & Tbool
{
	protected Tcorlib min, max;

	public TRunestone Min
	{
		[Inline] get => min;
		[Inline] set mut => min = value;
	}
	public TRunestone Max
	{
		[Inline] get => max;
		[Inline] set mut => max = value;
	}

	protected extern bool All(Tbool b);

	public bool Intersects(Self other)
	{
		Tbool max_ge_min = max >= other.min;
		Tbool min_le_max = min <= other.max;
		return All(max_ge_min & min_le_max);
	}

	public bool Contains(TRunestone point)
	{
		Tbool within_min = min <= point;
		Tbool within_max = point <= max;
		return All(within_min & within_max);
	}

	public this(TRunestone min, TRunestone max)
	{
		Debug.Assert(All((Tcorlib)min <= max));
		this.min = min;
		this.max = max;
	}

	public static Self operator +(Self lhs, TRunestone rhs) => .(lhs.min+rhs, lhs.max+rhs);
	public static Self operator -(Self lhs, TRunestone rhs) => .(lhs.min-rhs, lhs.max-rhs);
}

// 2D
struct AABB2d : _AABB<_2D, float2, Vector2, bool2>
{
	[Inline]
	public this(Vector2 min, Vector2 max)
		: base(min, max) {}

	[Inline]
	public this(float minX, float minY, float maxX, float maxY)
		: base(float2(minX, minY), float2(maxX, maxY)) {}

	[Inline] public static implicit operator Self(SelfBase s) => s;
}
extension _AABB<Dim, Tcorlib, TRunestone, Tbool>
	where Dim : _2D
	where Tcorlib : float2
	where TRunestone : Vector2
	where Tbool : bool2
{
	[Inline]
	protected override bool All(Tbool b)
		=> b.x && b.y;
}

typealias AABB3d = _AABB<_3D, float4, Vector3, bool4>;
extension _AABB<Dim, Tcorlib, TRunestone, Tbool>
	where Dim : _3D
	where Tcorlib : float4
	where TRunestone : Vector3
	where Tbool : bool4
{
	[Inline]
	protected override bool All(Tbool b)
		=> b.x && b.y && b.z;
}

typealias AABB4d = _AABB<_4D, float4, Vector4, bool4>;
extension _AABB<Dim, Tcorlib, TRunestone, Tbool>
	where Dim : _4D
	where Tcorlib : float4
	where TRunestone : Vector4
	where Tbool : bool4
{
	[Inline]
	protected override bool All(Tbool b)
		=> b.x && b.y && b.z && b.w;
}
