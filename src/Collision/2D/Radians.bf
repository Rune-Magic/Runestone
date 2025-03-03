using System;

namespace Runestone.Collision;

struct radians : float
{
	public const Self Up = Math.PI_f * 0.5f;
	public const Self Down = Math.PI_f * 1.5f;
	public const Self Right = 0f;
	public const Self Left = Math.PI_f;

	public static Self FromDegrees(float degrees)
		=> Math.DegreesToRadians(degrees);

	public float ToDegrees()
		=> Math.RadiansToDegrees(this);

	private this() {}

	[Inline] public static implicit operator SelfBase(Self s) => (.)s;
	[Inline] public static implicit operator Self(SelfBase s) => (.)s;
}
