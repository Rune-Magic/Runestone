using System;
using System.Collections;
using System.Diagnostics;

using Runestone;
using internal Runestone.Collision.CollisionObject2D;

namespace Runestone.Collision;

struct CollisionResult2D
{
	public bool areOverlapping;
	/// add the vector to the position to resolve the collision
	public Vector2 traslationVector;
	//public Vector2 intersectionPoint;

	[NoDiscard]
	public static Self Compute(CollisionObject2D obj1, CollisionObject2D obj2, bool computeTranslationVectors)
	{
		Self result = default;
		if (!obj1.aabb.Intersects(obj2.aabb))
			return result;

		nonCompound: do
		{
			switch (obj1.Shape)
			{
			case .Circle:
				switch (obj2.Shape)
				{
				case .Circle:
					result.areOverlapping = Collision2D.CircleToCircle(obj1, obj2);
				case .Capsule:
					result.areOverlapping = Collision2D.CircleToCapsule(obj1, obj2);
				case .Rectangle, .ConvexPolygon:
					result.areOverlapping = Collision2D.CricleToPolygon(obj1, obj2);
				case .Compound:
					break nonCompound;
				}
			case .Capsule:
				switch (obj2.Shape)
				{
				case .Circle:
					result.areOverlapping = Collision2D.CircleToCapsule(obj2, obj1);
				case .Capsule:
					result.areOverlapping = Collision2D.CapsuleToCapsule(obj1, obj2);
				case .Rectangle, .ConvexPolygon:
					result.areOverlapping = Collision2D.CapsuleToPolygon(obj1, obj2);
				case .Compound:
					break nonCompound;
				}
			case .Rectangle, .ConvexPolygon:
				switch (obj2.Shape)
				{
				case .Circle:
					result.areOverlapping = Collision2D.CricleToPolygon(obj2, obj1);
				case .Capsule:
					result.areOverlapping = Collision2D.CapsuleToPolygon(obj2, obj1);
				case .Rectangle, .ConvexPolygon:
					result.areOverlapping = Collision2D.PolygonToPolygon(obj1, obj2);
				case .Compound:
					break nonCompound;
				}
			case .Compound:
				break nonCompound;
			}

			return result;
		}

		let compound = obj2.cache as CollisionObject2D.CompoundCache;
		for (let object in compound.objects)
		{
			if (!obj1.aabb.Intersects(object.aabb)) continue;
			Vector2 old = result.traslationVector;
			result = Compute(obj1, object, computeTranslationVectors);
			if (!result.areOverlapping) continue;
			result.traslationVector += old;
			if (!computeTranslationVectors) break;
		}

		return result;
	}
}