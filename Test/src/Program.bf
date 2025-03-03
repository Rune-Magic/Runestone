using System;
using System.Collections;
using System.Diagnostics;

using Runestone;
using Runestone.Rendering;
using Runestone.Resources;

namespace Runestone.Test;

class Program : RunestoneApplication
{
	public override Settings Settings => .()
	{
		WindowName = "Test",
		WindowDimensions = .Ratio(3, 2),
		RenderSettings = .(),
	}

	public static void Main()
	{
		scope Self().RunApplication();
	}
}
