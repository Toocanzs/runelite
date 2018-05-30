package net.runelite.client.plugins.magetrainingarena;

import net.runelite.api.Point;

public enum TelekineticPuzzle
{
	PUZZLE_1(
			new Point(145, 86),
			new Point(136, 86),
			new TelekineticStep(new Point(-9, -9), new Point(-9, -10)),
			new TelekineticStep(new Point(-5, -9), new Point(1, -9)),
			new TelekineticStep(new Point(-5, -3), new Point(0, 1)),
			new TelekineticStep(new Point(-7, -3), new Point(-10, 0)),
			new TelekineticStep(new Point(-7, -6), new Point(-9, -10)),
			new TelekineticStep(new Point(0, -6), new Point(1, -9)),
			new TelekineticStep(new Point(0, 0), new Point(0, 1))
	),
	PUZZLE_2(
			new Point(143, 73),
			new Point(134, 73),
			new TelekineticStep(new Point(-9, 9), new Point(0, 10)),
			new TelekineticStep(new Point(-6, 9), new Point(1, 0)),
			new TelekineticStep(new Point(-6, 0), new Point(0, -1)),
			new TelekineticStep(new Point(-3, 0), new Point(1, 9)),
			new TelekineticStep(new Point(-3, 9), new Point(0, 10)),
			new TelekineticStep(new Point(0, 9), new Point(1, 0)),
			new TelekineticStep(new Point(0, 0), new Point(0, -1))
	),
	PUZZLE_3(
			new Point(142, 84),
			new Point(143, 80),
			new TelekineticStep(new Point(5, -4), new Point(6, -4)),
			new TelekineticStep(new Point(5, -9), new Point(5, -10)),
			new TelekineticStep(new Point(0, -9), new Point(-5, -9)),
			new TelekineticStep(new Point(0, -4), new Point(-4, 1)),
			new TelekineticStep(new Point(-4, -4), new Point(-5, 0)),
			new TelekineticStep(new Point(-4, 0), new Point(0, 1)),
			new TelekineticStep(new Point(0, 0), new Point(6, 0))

	),
	PUZZLE_4(
			new Point(153, 80),
			new Point(151, 84),
			new TelekineticStep(new Point(-2, 7), new Point(-2, 10)),
			new TelekineticStep(new Point(-4, 7), new Point(-8, 7)),
			new TelekineticStep(new Point(-4, 3), new Point(-7, -1)),
			new TelekineticStep(new Point(0, 3), new Point(3, 0)),
			new TelekineticStep(new Point(0, 8), new Point(2, 10)),
			new TelekineticStep(new Point(-6, 8), new Point(-8, 8)),
			new TelekineticStep(new Point(-6, 0), new Point(-7, -1)),
			new TelekineticStep(new Point(0, 0), new Point(3, 0))
	),
	PUZZLE_5(
			new Point(141, 68),
			new Point(150, 77),
			new TelekineticStep(new Point(9, 0), new Point(9, -1)),
			new TelekineticStep(new Point(8, 0), new Point(-1, 0)),
			new TelekineticStep(new Point(8, 8), new Point(0, 10)),
			new TelekineticStep(new Point(6, 8), new Point(-1, 2)),
			new TelekineticStep(new Point(6, 2), new Point(0, -1)),
			new TelekineticStep(new Point(2, 2), new Point(-1, 0)),
			new TelekineticStep(new Point(2, 0), new Point(0, -1)),
			new TelekineticStep(new Point(0, 0), new Point(-1, 0))
	),
	PUZZLE_6(
			new Point(135, 80),
			new Point(136, 72),
			new TelekineticStep(new Point(1, -7), new Point(1, 1)),
			new TelekineticStep(new Point(3, -7), new Point(9, 0)),
			new TelekineticStep(new Point(3, -3), new Point(8, 1)),
			new TelekineticStep(new Point(-1, -3), new Point(-2, 0)),
			new TelekineticStep(new Point(-1, -1), new Point(3, 1)),
			new TelekineticStep(new Point(6, -1), new Point(9, 0)),
			new TelekineticStep(new Point(6, 0), new Point(1, 1)),
			new TelekineticStep(new Point(0, 0), new Point(-2, 0))
	),
	PUZZLE_7(
			new Point(145, 86),
			new Point(146, 86),
			new TelekineticStep(new Point(1, -5), new Point(4, -10)),
			new TelekineticStep(new Point(0, -5), new Point(-3, -9)),
			new TelekineticStep(new Point(0, -7), new Point(-2, -10)),
			new TelekineticStep(new Point(1, -7), new Point(8, -9)),
			new TelekineticStep(new Point(1, -9), new Point(7, -10)),
			new TelekineticStep(new Point(4, -9), new Point(8, -7)),
			new TelekineticStep(new Point(4, -1), new Point(7, 1)),
			new TelekineticStep(new Point(0, -1), new Point(-3, 0)),
			new TelekineticStep(new Point(0, 0), new Point(-2, 1))
	),
	PUZZLE_8(
			new Point(139, 83),
			new Point(148, 74),
			new TelekineticStep(new Point(9, 0), new Point(9, 1)),
			new TelekineticStep(new Point(6, 0), new Point(-1, -4)),
			new TelekineticStep(new Point(6, -8), new Point(0, -10)),
			new TelekineticStep(new Point(3, -8), new Point(-1, 0)),
			new TelekineticStep(new Point(3, 0), new Point(0, 1)),
			new TelekineticStep(new Point(2, 0), new Point(-1, -9)),
			new TelekineticStep(new Point(2, -9), new Point(0, -10)),
			new TelekineticStep(new Point(0, -9), new Point(-1, 0)),
			new TelekineticStep(new Point(0, 0), new Point(0, 1))
	),
	PUZZLE_9(
			new Point(143, 82),
			new Point(141, 78),
			new TelekineticStep(new Point(-2, -1), new Point(-2, 1)),
			new TelekineticStep(new Point(-1, -1), new Point(4, 0)),
			new TelekineticStep(new Point(-1, -4), new Point(3, -10)),
			new TelekineticStep(new Point(2, -4), new Point(4, -9)),
			new TelekineticStep(new Point(2, -6), new Point(3, -10)),
			new TelekineticStep(new Point(-1, -6), new Point(-7, -9)),
			new TelekineticStep(new Point(-1, -5), new Point(-6, 1)),
			new TelekineticStep(new Point(3, -5), new Point(4, 0)),
			new TelekineticStep(new Point(3, 0), new Point(-1, 1)),
			new TelekineticStep(new Point(0, 0), new Point(-7, 0))
	),
	PUZZLE_10(
			new Point(147, 82),
			new Point(143, 73),
			new TelekineticStep(new Point(-4, -6), new Point(-9, 1)),
			new TelekineticStep(new Point(-8, -6), new Point(-10, 0)),
			new TelekineticStep(new Point(-8, -4), new Point(-5, 1)),
			new TelekineticStep(new Point(-5, -4), new Point(1, 0)),
			new TelekineticStep(new Point(-5, -2), new Point(-4, 1)),
			new TelekineticStep(new Point(-7, -2), new Point(-10, 0)),
			new TelekineticStep(new Point(-7, -3), new Point(-9, -10)),
			new TelekineticStep(new Point(-9, -3), new Point(-10, -8)),
			new TelekineticStep(new Point(-9, 0), new Point(-9, 1)),
			new TelekineticStep(new Point(0, 0), new Point(1, 0))
	);
	Point endLocation;
	Point guardianStart;
	TelekineticStep[] steps;

	static TelekineticPuzzle findByGuardianAndEnd(Point goalLocation, Point guardianNPClocation)
	{
		for (TelekineticPuzzle puzzle : values())
		{
			if (puzzle.guardianStart.equals(guardianNPClocation) && puzzle.endLocation.equals(goalLocation))
			{
				return puzzle;
			}
		}
		return null;
	}

	TelekineticPuzzle(Point endLocation, Point guardianStart, TelekineticStep... steps)
	{
		this.endLocation = endLocation;
		this.guardianStart = guardianStart;
		this.steps = steps;
	}
}
