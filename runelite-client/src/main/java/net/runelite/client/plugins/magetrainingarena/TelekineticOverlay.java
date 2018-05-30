package net.runelite.client.plugins.magetrainingarena;

import net.runelite.api.Client;
import net.runelite.api.Perspective;
import net.runelite.api.Point;
import net.runelite.api.Tile;
import net.runelite.api.coords.LocalPoint;
import net.runelite.client.ui.overlay.Overlay;
import net.runelite.client.ui.overlay.OverlayLayer;
import net.runelite.client.ui.overlay.OverlayPosition;
import net.runelite.client.ui.overlay.OverlayPriority;
import net.runelite.client.ui.overlay.OverlayUtil;

import java.awt.Color;
import java.awt.Dimension;
import java.awt.Graphics2D;
import java.awt.Polygon;

public class TelekineticOverlay extends Overlay
{
	private final Client client;
	private final MageTrainingArenaPlugin plugin;

	private final Color currentTargetColor = Color.CYAN;
	private final Color nextTargetColor = Color.RED;

	TelekineticOverlay(Client client, MageTrainingArenaPlugin plugin)
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
		final Tile[] playerTargetTiles = plugin.getPlayerTargetTiles();
		final Tile[] guardianTargetTiles = plugin.getGuardianTargetTiles();

		if (playerTargetTiles[0] != null)
		{
			renderTile(graphics, playerTargetTiles[0].getLocalLocation(), currentTargetColor);
		}
		if (playerTargetTiles[1] != null)
		{
			renderTile(graphics, playerTargetTiles[1].getLocalLocation(), nextTargetColor);
		}

		if (guardianTargetTiles[0] != null)
		{
			renderTile(graphics, guardianTargetTiles[0].getLocalLocation(), currentTargetColor.darker());
		}
		if (guardianTargetTiles[1] != null)
		{
			renderTile(graphics, guardianTargetTiles[1].getLocalLocation(), nextTargetColor.darker());
		}

		return null;
	}

	private void renderTile(Graphics2D graphics, LocalPoint localPoint, Color color)
	{
		Polygon poly = Perspective.getCanvasTilePoly(client, localPoint);
		if (poly == null)
		{
			return;
		}

		OverlayUtil.renderPolygon(graphics, poly, color);
	}

}
