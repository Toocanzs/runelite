package net.runelite.client.plugins.magetrainingarena;

public enum GraveyardBone
{
	BONE_1(1, 6904),
	BONE_2(2, 6905),
	BONE_3(3, 6906),
	BONE_4(4, 6907);

	int itemId;
	int fruitAmount;

	GraveyardBone(int fruitAmount, int itemId)
	{
		this.itemId = itemId;
		this.fruitAmount = fruitAmount;
	}

	static GraveyardBone GetBoneById(int itemId)
	{
		for (GraveyardBone bone : values())
		{
			if (itemId == bone.itemId)
			{
				return bone;
			}
		}
		return null;
	}
}
