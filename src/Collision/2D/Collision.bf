using System;
using System.Numerics;
using System.Diagnostics;

using Runestone;
using internal Runestone.Collision.CollisionObject2D;

namespace Runestone.Collision;

static class Collision2D
{
	// Vector Rotation
	public static Vector2 RotatePoint(Vector2 point, radians angle)
		=> RotatePoint(point, Math.Sin(angle), Math.Cos(angle));

	public static Vector2 RotatePoint(Vector2 point, float sinAngle, float cosAngle)
		=> .(
			cosAngle*point.X - sinAngle*point.Y,
			sinAngle*point.X + cosAngle*point.Y
		);

	public static Vector2 RotatePoint(Vector2 point, Vector2 anchor, radians angle)
		=> RotatePoint(point - anchor, angle) + anchor;

	public static Vector2 RotatePoint(Vector2 point, Vector2 anchor, float sinAngle, float cosAngle)
		=> RotatePoint(point - anchor, sinAngle, cosAngle) + anchor;

	/// @brief Line Segment Intersect
	///
	/// tests if line segment p1q1 intersects with p2q2
	/// if the do store the relative offset from p1 to q1 in t.x and p2 to q2 in t.y
	///
	///               p2
	///               |
	///               | t.y*|p2q2|
	///    t.x*|p1q1| |
	/// p1---------------------q1
	///               | 
	///               q2
	public static bool LineSegmentIntersect(Vector2 p1, Vector2 q1, Vector2 p2, Vector2 q2, out Vector2 t)
	{
		float x = Vector2.Cross(q1 - p1, q2 - p2);
		t = .(
			Vector2.Cross(p2 - p1, q2 - p2) / x,
			-(Vector2.Cross(p2 - p1, q1 - p1) / x)
		);
		bool2 b2 = (float2)t >= 0f;
		b2 &= (float2)t <= 1f;
		return b2.x && b2.y;
	}

	/// returns the point on a line nearest to the origin point
	public static Vector2 NearestPointOnLine(Vector2 origin, Vector2 start, Vector2 end)
	{
		let startToEnd = end - start;
		let offset = (start - origin).Dot(startToEnd);
		let length = startToEnd.Length;
		if (offset < 0) return start;
		if (offset > length) return end;
		return (startToEnd / length) * offset;
	}

	public enum Orientation
	{
		Collinear,
		ClockWise,
		CounterClockWise,
	}

	public static Orientation GetOrientation(Vector2 p1, Vector2 p2, Vector2 p3)
	{
	    float val = (p2.Y - p1.Y) * (p3.X - p2.X) - (p2.X - p1.X) * (p3.Y - p2.Y);
	 
	    if (Math.Abs(val) < float.Epsilon) return .Collinear;
	    return (val > 0) ? .ClockWise : .CounterClockWise; 
	}

	///////////////////////////////////////////////////////////////////////////////
	/////////////////////////////// Collisions ////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////

	public static bool TriangleToPoint(Vector2 A, Vector2 B, Vector2 C, Vector2 point)
	{
		float c1 = Vector2.Cross(B - A, point - A);
		float c2 = Vector2.Cross(C - B, point - B);
		float c3 = Vector2.Cross(A - C, point - C);
		return (c1 >= 0 && c2 >= 0 && c3 >= 0)
			&& (c3 <  0 && c2 <  0 && c3 <  0);
	}

	public static bool CircleToCircle(Vector2 p1, float r1, Vector2 p2, float r2)
	{
		let dist = p1.DistanceToSquared(p2);
		let radSum = r1 + r2;
		return dist <= radSum*radSum;
	}

	public static bool CircleToCircle(CollisionObject2D c1, CollisionObject2D c2)
	{
		Runtime.Assert(c1.Shape case .Circle(let r1));
		Runtime.Assert(c2.Shape case .Circle(let r2));
		return CircleToCircle(c1.Position, r1, c2.Position, r2);
	}

	public static bool CircleToCapsule(CollisionObject2D circle, CollisionObject2D capsule)
	{
		Runtime.Assert(circle.Shape case .Circle(let circleRadius));
		Runtime.Assert(capsule.Shape case .Capsule(let capsuleRadius, let start, ?));
		let cCapsule = capsule.cache as CollisionObject2D.CapsuleCache;
		return CircleToCircle(
			circle.Position, circleRadius,
			Collision2D.NearestPointOnLine(circle.Position, start, cCapsule.endPoint), capsuleRadius
		);
	}

	public static Vector2 SATPolygonProjection(Vector2 axisProj, Vector2[] vertices)
	{
		Vector2 minMax = .(float.MaxValue, float.MinValue);
		for (let point in vertices)
		{
			float q = point.Dot(axisProj);
			minMax.X = Math.Min(minMax.X, q);
			minMax.Y = Math.Min(minMax.Y, q);
		}
		return minMax;
	}

	public static bool PolygonToPolygon(CollisionObject2D poly1, CollisionObject2D poly2)
	{
		let cPoly1 = poly1.cache as CollisionObject2D.PolygonCache;
		let cPoly2 = poly2.cache as CollisionObject2D.PolygonCache;

		// Separated Axis Theorem (SAT)
		CollisionObject2D.PolygonCache cache = cPoly1;
		Vector2[] vertecies1 = cPoly1.verticies;
		Vector2[] vertecies2 = cPoly2.verticies;

		for (int shape < 2)
		{
			if (shape == 1)
			{
				cache = cPoly2;
				vertecies1 = cPoly2.verticies;
				vertecies2 = cPoly1.verticies;
			}

			for (int i < vertecies1.Count)
			{
				let axisProj = cache.satProjAxi[i];
				let r1 = cache.satProjections[i];
				let r2 = SATPolygonProjection(axisProj, vertecies2);

				if (!(r2.Y >= r1.X && r1.Y >= r2.X))
					return false;
			}
		}

		return true;
	}

	public static bool CircleToAABB(CollisionObject2D circle, AABB2d aabb)
	{
		Runtime.Assert(circle.Shape case .Circle(let radius));
		Vector2 nearest = .(
			Math.Clamp(circle.Position.X, aabb.Min.X, aabb.Max.X),
			Math.Clamp(circle.Position.Y, aabb.Min.Y, aabb.Max.Y)
		);
		return nearest.DistanceToSquared(circle.Position) <= radius*radius;
	}

	public static bool CricleToPolygon(CollisionObject2D circle, CollisionObject2D polygon)
	{
		Runtime.Assert(circle.Shape case .Circle(let radius));
		let cPolygon = polygon.cache as CollisionObject2D.PolygonCache;
		if (cPolygon.unrotatedRect) return CircleToAABB(circle, polygon.aabb);

		for (let i <= cPolygon.verticies.Count)
		{
			Vector2 axis;
			Vector2 polyProj;
			if (i == cPolygon.verticies.Count)
			{
				Vector2 closest = ?;
				float distance = float.MaxValue;
				for (let vertex in cPolygon.verticies)
				{
					let dist = vertex.DistanceToSquared(circle.Position);
					if (dist < distance)
						closest = vertex;
				}
				axis = closest.Normalized;
				polyProj = Collision2D.SATPolygonProjection(axis, cPolygon.verticies);
			}
			else
			{
				axis = cPolygon.satProjAxi[i];
				polyProj = cPolygon.satProjections[i];
			}

			let circleProj = circle.Position.Dot(axis);
			if (!(polyProj.Y >= circleProj-radius && circleProj+radius >= polyProj.X))
				return false;
		}

		return true;
	}

	public static void SATCapsuleProjection(out float capsuleProjMin, out float capsuleProjMax, Vector2 projAxis, Vector2 start, Vector2 end, float radius)
	{
		capsuleProjMin = start.Dot(projAxis) - radius;
		capsuleProjMax = end.Dot(projAxis) + radius;
		if (capsuleProjMin > capsuleProjMax)
			Swap!(ref capsuleProjMin, ref capsuleProjMax);
	}

	public static bool CapsuleToPolygon(CollisionObject2D capsule, CollisionObject2D polygon)
	{
		Runtime.Assert(capsule.Shape case .Capsule(let radius, let capsuleStart, ?));
		let cCapsule = capsule.cache as CollisionObject2D.CapsuleCache;
		let cPolygon = polygon.cache as CollisionObject2D.PolygonCache;

		for (let i <= cPolygon.verticies.Count + 1)
		{
			Vector2 axis;
			Vector2 polyProj;
			if (i < cPolygon.verticies.Count)
			{
				axis = cPolygon.satProjAxi[i];
				polyProj = cPolygon.satProjections[i];
			}
			else
			{
				axis = cCapsule.satAxi[i-cPolygon.verticies.Count];
				polyProj = Collision2D.SATPolygonProjection(axis, cPolygon.verticies);
			}

			SATCapsuleProjection(let capsuleProjMin, let capsuleProjMax, axis, capsuleStart, cCapsule.endPoint, radius);
			if (!(polyProj.Y >= capsuleProjMin && capsuleProjMax >= polyProj.X))
				return false;
		}

		return true;
	}

	public static bool CapsuleToCapsule(CollisionObject2D capsule1, CollisionObject2D capsule2)
	{
		Runtime.Assert(capsule1.Shape case .Capsule(let radius1, let capsuleStart1, ?));
		let cCapsule1 = capsule1.cache as CollisionObject2D.CapsuleCache;
		Runtime.Assert(capsule2.Shape case .Capsule(let radius2, let capsuleStart2, ?));
		let cCapsule2 = capsule2.cache as CollisionObject2D.CapsuleCache;

		Vector2[4] axi = .(cCapsule1.satAxi[0], cCapsule1.satAxi[1], cCapsule2.satAxi[0], cCapsule2.satAxi[1]);
		for (let axis in axi)
		{
			SATCapsuleProjection(let min1, let max1, axis, capsuleStart1, cCapsule1.endPoint, radius1);
			SATCapsuleProjection(let min2, let max2, axis, capsuleStart2, cCapsule2.endPoint, radius2);
			if (!(max2 >= min1 && max1 >= min2))
				return false;
		}

		return true;
	}
}
