package net.runelite.client.plugins.tileindicators;

public enum TektonAnimation
{

	ENRAGED_SWORD_STAB(7493),
	ENRAGED_HAMMER_SWING(7492),
	ENRAGED_SWORD_SLASH(7494),
	SWORD_STAB(7482),
	HAMMER_SWING(7484),
	SWORD_SLASH(7483);

	public int animID;
	TektonAnimation(int animID)
	{
		this.animID = animID;
	}
}
