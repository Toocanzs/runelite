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

import com.google.common.eventbus.Subscribe;
import lombok.Getter;
import net.runelite.api.NPC;
import net.runelite.api.Query;
import net.runelite.api.coords.WorldPoint;
import net.runelite.api.events.GameTick;
import net.runelite.api.queries.NPCQuery;
import net.runelite.client.plugins.Plugin;
import net.runelite.client.plugins.PluginDescriptor;
import net.runelite.client.ui.overlay.OverlayManager;
import net.runelite.client.util.QueryRunner;

import javax.inject.Inject;

@PluginDescriptor(
		name = "Thieving Plugin",
		enabledByDefault = true
)
public class ThievingPlugin extends Plugin
{
	@Inject
	private OverlayManager overlayManager;

	@Inject
	private ThievingOverlay overlay;

	@Inject
	private QueryRunner queryRunner;

	@Getter
	private NPC masterFarmer = null;

	WorldPoint masterFarmerLastLocation = null;

	@Getter
	private int ticksSinceMasterMoved = 0;

	@Override
	protected void startUp() throws Exception
	{
		overlayManager.add(overlay);
	}

	@Override
	protected void shutDown() throws Exception
	{
		overlayManager.remove(overlay);
	}

	@Subscribe
	public void onTick(GameTick gameTick)
	{
		Query npcQuery = new NPCQuery().nameContains("Master Farmer");
		NPC[] result = queryRunner.runQuery(npcQuery);
		masterFarmer = result.length >= 1 ? result[0] : null;

		if(masterFarmer != null)
		{
			if(masterFarmerLastLocation != null)
			{
				if(masterFarmerLastLocation .equals(masterFarmer.getWorldLocation()))
				{
					ticksSinceMasterMoved++;
				}
				else
				{
					ticksSinceMasterMoved = 0;
				}
			}
			masterFarmerLastLocation = masterFarmer.getWorldLocation();
		}
		else
		{
			masterFarmerLastLocation = null;
		}

	}

}
