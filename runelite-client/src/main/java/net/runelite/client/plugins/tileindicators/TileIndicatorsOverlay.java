/*
 * Copyright (c) 2018, Tomas Slusny <slusnucky@gmail.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
package net.runelite.client.plugins.tileindicators;

import java.awt.Color;
import java.awt.Dimension;
import java.awt.Graphics2D;
import java.awt.Polygon;

import net.runelite.api.Client;
import net.runelite.api.NPC;
import net.runelite.api.Perspective;
import net.runelite.api.Point;
import net.runelite.api.Tile;
import net.runelite.api.Varbits;
import net.runelite.api.coords.LocalPoint;
import net.runelite.api.coords.WorldPoint;
import net.runelite.client.ui.overlay.Overlay;
import net.runelite.client.ui.overlay.OverlayLayer;
import net.runelite.client.ui.overlay.OverlayPosition;
import net.runelite.client.ui.overlay.OverlayPriority;
import net.runelite.client.ui.overlay.OverlayUtil;
import net.runelite.client.ui.overlay.components.ProgressPieComponent;

import javax.inject.Inject;

public class TileIndicatorsOverlay extends Overlay
{
	private final Client client;
	private final TileIndicatorsConfig config;
	private final Point[] pointsToMark = new Point[]{

			new Point(165, 166), //SE
			new Point(165, 173), //Middle north east
			new Point(165, 171), //Middle south east
			new Point(165, 178), //NE

			new Point(156, 166), //SW
			new Point(156, 178), //NW
			new Point(156, 173), //Middle north west
			new Point(156, 171)  //Middle south west
	};

	private TileIndicatorsPlugin plugin;

	@Inject
	TileIndicatorsOverlay(Client client, TileIndicatorsConfig config, TileIndicatorsPlugin plugin)
	{
		this.client = client;
		this.config = config;
		this.plugin = plugin;
		setPosition(OverlayPosition.DYNAMIC);
		setLayer(OverlayLayer.ABOVE_SCENE);
		setPriority(OverlayPriority.LOW);
	}

	@Override
	public Dimension render(Graphics2D graphics)
	{
		if (client.getPlane() == 0 && client.getVar(Varbits.IN_RAID) == 1)
		{

			Tile[][] tiles = client.getRegion().getTiles()[client.getPlane()];
			for (int i = 0; i < tiles.length; i++)
			{
				for (int j = 0; j < tiles[i].length; j++)
				{
					for (Point point : pointsToMark)
					{
						Tile curTile = tiles[i][j];
						if (curTile == null)
							continue;
						WorldPoint worldPoint = curTile.getWorldLocation();
						int x = (worldPoint.getX()) % 192;
						int y = (worldPoint.getY()) % 192;
						if (x == point.getX() && y == point.getY())
						{
							Polygon destinationPoly = Perspective.getCanvasTilePoly(client, tiles[i][j].getLocalLocation());
							if (destinationPoly != null)
								OverlayUtil.renderPolygon(graphics, destinationPoly, Color.gray);
						}
					}
				}
			}
		}

		if (client.getVar(Varbits.IN_RAID) == 1)
		{
			NPC tekton = plugin.getTekton();
			if (tekton != null)
			{
				drawTimerOnNpc(graphics, tekton, plugin.getTektonTicks(), 3);
			}
		}

		if (config.destinationTileEnabled())
		{
			LocalPoint dest = client.getLocalDestinationLocation();

			if (dest != null)
			{
				Polygon destinationPoly = Perspective.getCanvasTilePoly(client, dest);
				if (destinationPoly != null)
					OverlayUtil.renderPolygon(graphics, destinationPoly, config.highlightDestinationColor());
			}
		}

		if (config.occupiedTileEnabled())
		{
			LocalPoint occupied = LocalPoint.fromWorld(client, client.getLocalPlayer().getWorldLocation());
			if (occupied != null)
			{
				Polygon occupiedPoly = Perspective.getCanvasTilePoly(client, occupied);
				if (occupiedPoly != null)
					OverlayUtil.renderPolygon(graphics, occupiedPoly, config.highlightOccupiedColor());
			}
		}

		return null;
	}



	private void drawTimerOnNpc(Graphics2D graphics, NPC npc, int ticksLeft, int tickMax)
	{
		if (npc == null)
			return;
		if (npc.getWorldLocation().getPlane() != client.getPlane())
		{
			return;
		}
		LocalPoint localLoc = LocalPoint.fromWorld(client, npc.getWorldLocation());
		if (localLoc == null)
		{
			return;
		}


		net.runelite.api.Point loc = Perspective.worldToCanvas(client, localLoc.getX(), localLoc.getY(), npc.getWorldLocation().getPlane());

		double timeLeft = 1 - ((double) ticksLeft / tickMax);

		Color fill = Color.green;
		Color border = Color.black;

		ProgressPieComponent pie = new ProgressPieComponent();
		pie.setFill(fill);
		pie.setBorderColor(border);
		pie.setProgress(timeLeft);
		pie.setPosition(loc);
		pie.render(graphics);
	}
}