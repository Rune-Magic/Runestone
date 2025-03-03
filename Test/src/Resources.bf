using System;
using Runestone.Resources;

namespace Runestone.Test;

class Resources
{
	[Test]
	static void Shader()
	{
		uint8[?] span = Shader.Compile("res/shader.vert");
		Test.Assert(span.Count > 0);
	}
}