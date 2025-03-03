using System;
using System.Numerics;
using System.Diagnostics;
using System.Globalization;
using internal Runestone;

namespace Runestone;

interface IVector
{
	public float this[int idx] { get; set; }
}

internal struct _Vec<size, T> : IVector
	where size : const int
	where T :	operator T + T, operator T - T,
				operator T * T, operator T / T,
				operator T % T,
				operator T + float, operator T - float,
				operator T * float, operator T / float,
				operator T % float
{
	protected T underlying;

	[Inline] public float Length => Math.Sqrt(Dot(this));
	[Inline] public float LengthSquared => Math.Abs(Dot(this));

	[Inline]
	public float DistanceToSquared(Self other)
		=> (this - other).Length;

	[Inline]
	public float DistanceTo(Self other)
		=> Math.Sqrt(DistanceToSquared(other));

	[Optimize]
	public float Dot(Self other)
	{
	    float product = 0;
	    for (let i < size)
	        product += this[i] * other[i];
	    return product;
	}

	[Inline] public Self Normalized => this / Length;

	public extern float this[int idx] { get; set; }

	[Inline] public static implicit operator T(Self self) => self.underlying;
	[Inline] public static implicit operator Self(T self) => .() { underlying = self };

	[Inline, Commutable] public static Self operator+(Self a, Self b) => a.underlying + b.underlying;
	[Inline, Commutable] public static Self operator-(Self a, Self b) => a.underlying - b.underlying;
	[Inline, Commutable] public static Self operator*(Self a, Self b) => a.underlying * b.underlying;
	[Inline, Commutable] public static Self operator/(Self a, Self b) => a.underlying / b.underlying;
	[Inline, Commutable] public static Self operator%(Self a, Self b) => a.underlying % b.underlying;

	[Inline, Commutable] public static Self operator+(Self a, float b) => a.underlying + b;
	[Inline, Commutable] public static Self operator-(Self a, float b) => a.underlying - b;
	[Inline, Commutable] public static Self operator*(Self a, float b) => a.underlying * b;
	[Inline, Commutable] public static Self operator/(Self a, float b) => a.underlying / b;
	[Inline, Commutable] public static Self operator%(Self a, float b) => a.underlying % b;

	public override void ToString(String outString)
	{
		for (let i < size-1)
		{
			this[i].ToString(outString);
			outString.Append(",");
		}
		this[size-1].ToString(outString);
	}

	[Inline] public void ToString(String outString, String format) => ToString(outString, format, CultureInfo.CurrentCulture);
	public void ToString(String outString, String format, IFormatProvider formatProvider)
	{
		for (let i < size-1)
		{
			this[i].ToString(outString, format, formatProvider);
			outString.Append(",");
		}
		this[size-1].ToString(outString, format, formatProvider);
	}

	[Inline] public static implicit operator Vector2(Self s) => s;
	[Inline] public static implicit operator Vector3(Self s) => s;
	[Inline] public static implicit operator Vector4(Self s) => s;
}

extension _Vec<size, T> where T : float2
{
	public override float this[int idx]
	{
		[Inline] get => underlying[idx];
		[Inline] set => underlying[idx] = value;
	}
}

extension _Vec<size, T> where T : float4
{
	public override float this[int idx]
	{
		[Inline] get => underlying[idx];
		[Inline] set => underlying[idx] = value;
	}
}

struct Vector2 : _Vec<2, float2>
{
	public const Self Zero = .(0, 0);
	public const Self Up = .(0, -1);
	public const Self Down = .(0, 1);
	public const Self Left = .(-1, 0);
	public const Self Right = .(1, 0);

	public float X
	{
		[Inline] get => underlying.x;
		[Inline] set mut => underlying.x = value;
	}
	public float Y
	{
		[Inline] get => underlying.y;
		[Inline] set mut => underlying.y = value;
	}
	[Inline] public Self YX => underlying.yx;

	[Inline] public static implicit operator float2(Self self) => self.underlying;
	[Inline] public static implicit operator Self(float2 f2)
	{
		Self vec = default;
		vec.underlying = f2;
		return vec;
	}

	[Inline]
	public this(float x, float y)
		=> underlying = .(x, y);

	public static float Cross(Self a, Self b) => a.X*b.Y - a.Y*b.X;
}

struct Vector3 : _Vec<3, float4>
{
	public float X
	{
		[Inline] get => underlying.x;
		[Inline] set mut => underlying.x = value;
	}
	public float Y
	{
		[Inline] get => underlying.y;
		[Inline] set mut => underlying.y = value;
	}
	public float Z
	{
		[Inline] get => underlying.z;
		[Inline] set mut => underlying.z = value;
	}
	[Inline] public Self ZYX => .(Z, Y, X);

	[Inline] public static implicit operator float4(Self self) => self.underlying;
	[Inline] public static implicit operator Self(float4 f4)
	{
		Self vec = default;
		vec.underlying = f4;
		return vec;
	}

	[Inline]
	public this(float x, float y, float z)
	{
		underlying.x = x;
		underlying.y = y;
		underlying.z = z;
	}

	public new float this[int idx]
	{
		[Checked]
		get
		{
			Runtime.Assert(idx >= 0 && idx < 3);
			return underlying[idx];
		}
		[Unchecked, Inline] get => underlying[idx];
		[Checked]
		set
		{
			Runtime.Assert(idx >= 0 && idx < 3);
			underlying[idx] = value;
		}
		[Unchecked, Inline] set => underlying[idx] = value;
	}
}

struct Vector4 : _Vec<4, float4>
{
	public float X
	{
		[Inline] get => underlying.x;
		[Inline] set mut => underlying.x = value;
	}
	public float Y
	{
		[Inline] get => underlying.y;
		[Inline] set mut => underlying.y = value;
	}
	public float Z
	{
		[Inline] get => underlying.z;
		[Inline] set mut => underlying.z = value;
	}
	public float W
	{
		[Inline] get => underlying.w;
		[Inline] set mut => underlying.w = value;
	}
	[Inline] public Self WZYX => underlying.wzyx;

	[Inline]
	public this(float x, float y, float z, float w)
		=> underlying = .(x, y, z, w);

	[Inline] public static implicit operator float4(Self self) => self.underlying;
	[Inline] public static implicit operator Self(float4 f4)
	{
		Self vec = default;
		vec.underlying = f4;
		return vec;
	}
}
