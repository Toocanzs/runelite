package net.runelite.client.plugins.magetrainingarena;

public enum AlchemyRoomCabinet
{
	WEST_0(23684, 23685),
	WEST_1(23682, 23683),
	WEST_2(23680, 23681),
	WEST_3(23678, 23679),

	EAST_0(23686, 23687),
	EAST_1(23688, 23689),
	EAST_2(23690, 23691),
	EAST_3(23692, 23693);

	int closedObjectId;
	int openObjectId;
	AlchemyRoomCabinet(int closedObjectId, int openObjectId)
	{
		this.closedObjectId = closedObjectId;
		this.openObjectId = openObjectId;
	}

	static AlchemyRoomCabinet getCabinetById(int objectId)
	{
		for (AlchemyRoomCabinet cabinet : values())
		{
			if (cabinet.openObjectId == objectId || cabinet.closedObjectId == objectId)
			{
				return cabinet;
			}
		}
		return null;
	}
}
