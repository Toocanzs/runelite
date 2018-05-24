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

import com.google.common.eventbus.Subscribe;
import com.google.inject.Provides;
import javax.inject.Inject;

import lombok.Getter;
import net.runelite.api.Actor;
import net.runelite.api.Client;
import net.runelite.api.NPC;
import net.runelite.api.Query;
import net.runelite.api.events.AnimationChanged;
import net.runelite.api.events.GameTick;
import net.runelite.api.queries.NPCQuery;
import net.runelite.api.widgets.Widget;
import net.runelite.api.widgets.WidgetInfo;
import net.runelite.client.config.ConfigManager;
import net.runelite.client.plugins.Plugin;
import net.runelite.client.plugins.PluginDescriptor;
import net.runelite.client.ui.overlay.Overlay;
import net.runelite.client.util.QueryRunner;

@PluginDescriptor(
	name = "Tile Indicators",
	enabledByDefault = false
)
public class TileIndicatorsPlugin extends Plugin
{
	@Inject
	private Client client;

	@Inject
	private TileIndicatorsConfig config;

	private TileIndicatorsOverlay tileIndicatorsOverlay;

	@Provides
	TileIndicatorsConfig provideConfig(ConfigManager configManager)
	{
		return configManager.getConfig(TileIndicatorsConfig.class);
	}

	@Override
	protected void startUp() throws Exception
	{
		tileIndicatorsOverlay = new TileIndicatorsOverlay(client, config, this);
	}


	private int ticks = 0;
	@Subscribe
	public void onTick(GameTick gameTick)
	{
		ticks++;
		if (tektonTicks > 0)
			tektonTicks--;
	}

	@Getter
	private int tektonTicks = 3;
	private void resetTektonAttackTimer()
	{
		tektonTicks = 3;
	}

	@Inject
	private QueryRunner queryRunner;

	public NPC getTekton()
	{
		Query npcQuery = new NPCQuery().nameContains("Tekton");
		NPC[] result = queryRunner.runQuery(npcQuery);
		return result.length >= 1 ? result[0] : null;
	}

	@Subscribe
	public void onAnimation(AnimationChanged animationChanged)
	{
		if (animationChanged.getActor() != null)
		{
			Actor actor = animationChanged.getActor();
			if (actor.getName() != null && actor.getName().toLowerCase().contains("tekton"))
			{
				for (TektonAnimation tektonAnimation : TektonAnimation.values())
				{
					if (actor.getAnimation() == tektonAnimation.animID)
					{
						resetTektonAttackTimer();
					}
				}
			}
		}
	}

	@Override
	public Overlay getOverlay()
	{
		return tileIndicatorsOverlay;
	}
}
