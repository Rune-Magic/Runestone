using System;
using System.Diagnostics;
using System.Collections;
using Runestone;

namespace Runestone.Collision;

enum CollisionShape2D
{
	/// anchored at its center
	case Circle(float radius);
	/// anchored at its center
	/// widthExtend and heightExtend are half the width/height
	case Rectangle(float widthExtend, float heightExtend);
	/// anchored at 0,0
	case ConvexPolygon(Span<Vector2> points);
	/// anchored at it's start
	case Capsule(float radius, Vector2 start, Vector2 end);
	/// anchored at 0,0
	case Compound(Span<(Self shape, Vector2 offset)> shapes);

	/// anchored at 0,0
	public static Self ConcavePolygon(Span<Vector2> points, Collision2D.Orientation orientation, BumpAllocator alloc)
	{
		Debug.Assert(points.Length >= 3);
		Debug.Assert(orientation != .Collinear);

		// Triangulation
		(Self shape, Vector2 offset)[] triangles = new:alloc .[points.Length - 2];
		int trianglesSize = 0;
		void AddTriangle(params Vector2[3] p)
		{
			triangles[trianglesSize++] = (.ConvexPolygon(p), .Zero);
		}

		List<Vector2> vertices = scope .(points);
		var iter = vertices.GetEnumerator();

		whileLoop: while (true)
		{
			if (vertices.Count == 3)
			{
				AddTriangle(vertices[0], vertices[1], vertices[2]);
				break;
			}

			forLoop: for (let last in iter..Reset())
			{
				let current = vertices[(iter.Index + 1) % vertices.Count];
				let next = vertices[(iter.Index + 2) % vertices.Count];

				switch (Collision2D.GetOrientation(last, current, next))
				{
				case .Collinear: Internal.FatalError("No col-linear vertices");
				case orientation:
				default: continue;
				}

				for (let vertex in vertices)
				{
					if (Collision2D.TriangleToPoint(last, current, next, vertex))
						continue forLoop;
				}

				AddTriangle(last, current, next);
				continue whileLoop;
			}

			Runtime.FatalError("No intersecting edges");
		}

		return .Compound(triangles);
	}
}

class CollisionObject2D
{
	Vector2 position;
	radians rotation;
	CollisionShape2D shape;
	internal CachedData cache ~ DeleteCache!();
	public AABB2d aabb;
	private bool ownsCache = true;

	private mixin DeleteCache()
	{
		if (ownsCache) delete cache;
	}

	[Inline]
	private void Reevaluate()
	{
		DeleteCache!();
		cache = EvaluateCache();
		aabb = EvaluateAABB();
		ownsCache = true;
	}

	public Vector2 Position
	{
		[Inline] get => position;
		set
		{
			position = value;
			aabb = EvaluateAABB();
		}
	}

	public radians Rotation
	{
		[Inline] get => rotation;
		set
		{
			rotation = value;
			Reevaluate();
		}
	}

	public CollisionShape2D Shape
	{
		[Inline] get => shape;
		set
		{
			shape = value;
			Reevaluate();
		}
	}

	internal abstract class CachedData {}

	internal class PolygonCache : CachedData
	{
		public Vector2[] verticies ~ delete _;
		public Vector2[] satProjAxi ~ delete _;
		public Vector2[] satProjections ~ delete _;
		public bool unrotatedRect = false;
	}

	internal class CapsuleCache : CachedData
	{
		public Vector2 endPoint;
		public Vector2[2] satAxi;
	}

	internal class CompoundCache : CachedData
	{
		public bool ownsObjects = true;
		public CollisionObject2D[] objects ~
		{
			if (ownsObjects)
				DeleteContainerAndItems!(objects);
			else delete _;
		}
	}

	public this(CollisionShape2D shape, Vector2 position, radians rotation = 0.f)
	{
		this.shape = shape;
		this.position = position;
		this.rotation = rotation;
		this.cache = EvaluateCache();
		this.aabb = EvaluateAABB();
	}

	public this(CollisionObject2D obj)
	{
		this.shape = obj.shape;
		this.position = obj.position;
		this.rotation = obj.rotation;
		this.cache = obj.cache;
		ownsCache = false;
	}

	public this(CollisionObject2D obj, Vector2 newPosition) : this(obj)
	{
		Position = newPosition;
	}

	public this(params Span<CollisionObject2D> objects)
	{
		shape = .Compound(null);
		position = .Zero;
		rotation = 0f;
		cache = new CompoundCache()
		{
			ownsObjects = true,
			objects = objects.CopyTo(..new CollisionObject2D[objects.Length])
		};
	}

	[NoDiscard]
	internal CachedData EvaluateCache()
	{
		CachedData cache;
		float sinRotation = Math.Sin(rotation);
		float cosRotation = Math.Cos(rotation);
		switch (shape)
		{
		case .Circle(let radius):
			cache = null;
		case .Rectangle(let width, let height):
			if (Math.Abs(rotation) < float.Epsilon)
				cache = new PolygonCache()
				{
					verticies = new .[4](
						.(-width, height),
						.(width, height),
						.(width, -height),
						.(-width, -height)
					),
					unrotatedRect = true
				};
			else
				cache = new PolygonCache()
				{
					verticies = new .[4](
						Collision2D.RotatePoint(.(-width, height), sinRotation, cosRotation),
						Collision2D.RotatePoint(.(width, height), sinRotation, cosRotation),
						Collision2D.RotatePoint(.(width, -height), sinRotation, cosRotation),
						Collision2D.RotatePoint(.(-width, -height), sinRotation, cosRotation)
					)
				};
		case .ConvexPolygon(let points):
			Debug.Assert(points.Length > 1);
			let anchor = points[0];
			PolygonCache polygon = new .() { verticies = new .[points.Length] };
			polygon.verticies[0] = anchor;
			var iter = points.GetEnumerator()..MoveNext();
			for (let point in iter)
			{
				polygon.verticies[iter.Index] = Collision2D.RotatePoint(point, anchor, sinRotation, cosRotation);
			}
			cache = polygon;
		case .Capsule(let radius, let start, let end):
			let endPoint = Collision2D.RotatePoint(end, start, sinRotation, cosRotation);
			Vector2 vec = endPoint - start;
			cache = new CapsuleCache()
			{
				endPoint = endPoint,
				satAxi = .(
					vec.YX.Normalized,
					vec.Normalized,
				)
			};
		case .Compound(let shapes):
			CompoundCache compound = new .() { objects = new .[shapes.Length] };

			for (let entry in shapes)
				compound.objects[@entry.Index] = new .(entry.shape, entry.offset, rotation);

			cache = compound;
		}
		if (let polygon = cache as PolygonCache)
		{
			polygon.satProjAxi = new .[polygon.verticies.Count];
			polygon.satProjections = new .[polygon.verticies.Count];
			for (let a < polygon.verticies.Count)
			{
				let b = (a + 1) % polygon.verticies.Count;
				Vector2 vec = polygon.verticies[b] - polygon.verticies[a];
				polygon.satProjAxi[a] = vec.YX.Normalized;
				polygon.satProjections[a] = Collision2D.SATPolygonProjection(polygon.satProjAxi[a], polygon.verticies);
			}
		}
		return cache;
	}

	[NoDiscard]
	protected AABB2d EvaluateAABB()
	{
		AABB2d aabb;
		switch (shape)
		{
		case .Circle(let radius):
			aabb = .(
				position - radius,
				position + radius
			);
		case .Rectangle, .ConvexPolygon:
			let polygon = cache as PolygonCache;
			float minX = float.MaxValue;
			float minY = float.MaxValue;
			float maxX = float.MinValue;
			float maxY = float.MinValue;

			for (var vertex in polygon.verticies)
			{
				vertex += position;
				minX = Math.Min(vertex.X + position.X, minX);
				minY = Math.Min(vertex.Y + position.Y, minY);
				maxX = Math.Max(vertex.X + position.X, maxX);
				maxY = Math.Max(vertex.Y + position.Y, maxY);
			}

			aabb = .(minX, minY, maxX, maxY);
		case .Capsule(let radius, let start, ?):
			let capsule = cache as CapsuleCache;
			aabb = .(
				Math.Min(start.X, capsule.endPoint.X), Math.Min(start.Y, capsule.endPoint.Y),
				Math.Max(start.X, capsule.endPoint.X), Math.Max(start.Y, capsule.endPoint.Y)
			);
			aabb.Min -= radius;
			aabb.Max += radius;
		case .Compound:
			let compound = cache as CompoundCache;
			float minX = float.MaxValue;
			float minY = float.MaxValue;
			float maxX = float.MinValue;
			float maxY = float.MinValue;

			for (let boundingBox in compound.objects)
			{
				minX = Math.Min(boundingBox.aabb.Min.X, minX);
				minY = Math.Min(boundingBox.aabb.Min.Y, minY);
				maxX = Math.Max(boundingBox.aabb.Max.X, maxX);
				maxY = Math.Max(boundingBox.aabb.Max.Y, maxY);
			}

			aabb = .(minX, minY, maxX, maxY) + position;
		}
		return aabb;
	}
}
