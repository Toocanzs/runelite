package net.runelite.client.plugins.magetrainingarena;

import net.runelite.api.ItemID;

public enum AlchemyRoomItem
{
	ADAMANT_KITESHIELD("Adamant kiteshield", ItemID.ADAMANT_KITESHIELD),
	LEATHER_BOOTS("Leather boots", ItemID.LEATHER_BOOTS),
	ADAMANT_MED_HELM("Adamant med helm", ItemID.ADAMANT_MED_HELM),
	EMERALD("Emerald", ItemID.EMERALD),
	RUNE_LONGSWORD("Rune longsword", ItemID.RUNE_LONGSWORD);

	int itemID;
	String name;
	AlchemyRoomItem(String name, int itemID)
	{
		this.itemID = itemID;
		this.name = name;
	}
}
