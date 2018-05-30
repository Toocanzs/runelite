package net.runelite.client.plugins.magetrainingarena;

import lombok.Getter;
import net.runelite.api.Point;

public class TelekineticStep
{
	//Points are relative offsets of the end goal location for this puzzle

	//Where the guardian needs to go for this step of the puzzle
	@Getter
	Point guardianTargetOffset;

	//Where the player should stand to move the guardian
	@Getter
	Point playerTargetOffset;

	public TelekineticStep(Point guardianTaretLocation, Point playerTargetOffset)
	{
		this.guardianTargetOffset = guardianTaretLocation;
		this.playerTargetOffset = playerTargetOffset;
	}
}
