/*
 * Copyright (c) 2018, Toocanzs <https://github.com/Toocanzs>
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
package net.runelite.client.plugins.thieving;

import net.runelite.api.Client;
import net.runelite.api.NPC;
import net.runelite.api.Perspective;
import net.runelite.api.Point;
import net.runelite.api.coords.LocalPoint;
import net.runelite.client.ui.overlay.Overlay;
import net.runelite.client.ui.overlay.OverlayLayer;
import net.runelite.client.ui.overlay.OverlayPosition;
import net.runelite.client.ui.overlay.OverlayPriority;
import net.runelite.client.ui.overlay.components.ProgressPieComponent;

import javax.inject.Inject;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.Graphics2D;

public class ThievingOverlay extends Overlay
{
	private final Client client;
	private final ThievingPlugin plugin;
	private final int MAX_TICKS_TILL_RESET = 500;

	@Inject
	private ThievingOverlay(Client client, ThievingPlugin plugin)
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
		NPC masterFarmer = plugin.getMasterFarmer();
		if(masterFarmer == null)
		{
			return null;
		}
		drawTimerOnNpc(graphics, masterFarmer, plugin.getTicksSinceMasterMoved(), MAX_TICKS_TILL_RESET);
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


		Point loc = Perspective.worldToCanvas(client, localLoc.getX(), localLoc.getY(), npc.getWorldLocation().getPlane());

		double timeLeft = 1 - ((double) ticksLeft / tickMax);

		final Color fill = Color.red;
		final Color border = Color.black;

		ProgressPieComponent pie = new ProgressPieComponent();
		pie.setFill(fill);
		pie.setBorderColor(border);
		pie.setProgress(timeLeft);
		pie.setPosition(loc);
		pie.render(graphics);
	}
}
