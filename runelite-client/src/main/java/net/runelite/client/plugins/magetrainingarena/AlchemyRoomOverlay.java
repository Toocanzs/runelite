package net.runelite.client.plugins.magetrainingarena;

import net.runelite.api.Client;
import net.runelite.api.GameObject;
import net.runelite.api.coords.LocalPoint;
import net.runelite.client.ui.overlay.Overlay;
import net.runelite.client.ui.overlay.OverlayLayer;
import net.runelite.client.ui.overlay.OverlayPosition;
import net.runelite.client.ui.overlay.OverlayPriority;
import net.runelite.client.ui.overlay.OverlayUtil;

import java.awt.Dimension;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;

public class AlchemyRoomOverlay extends Overlay
{
	private final Client client;
	private final MageTrainingArenaPlugin plugin;

	AlchemyRoomOverlay(Client client, MageTrainingArenaPlugin plugin)
	{
		this.client = client;
		this.plugin = plugin;
		setPosition(OverlayPosition.DYNAMIC);
		setLayer(OverlayLayer.ABOVE_SCENE);
		setPriority(OverlayPriority.LOW);
	}



	@Override
	public Dimension render(Graphics2D graphics)
	{
		GameObject[] cabinets = plugin.getCabinets();
		if (cabinets != null)
		{
			for (GameObject cabinet : cabinets)
			{
				BufferedImage image = plugin.getCabinetItemImage(cabinet.getId());
				LocalPoint localLoc = LocalPoint.fromWorld(client, cabinet.getWorldLocation());
				if (image == null || localLoc == null)
					continue;
				OverlayUtil.renderImageLocation(client, graphics, localLoc, image, 100);
			}
		}
		return null;
	}


}
