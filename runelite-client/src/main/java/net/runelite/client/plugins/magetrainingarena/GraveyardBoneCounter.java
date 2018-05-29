package net.runelite.client.plugins.magetrainingarena;

import net.runelite.client.ui.overlay.infobox.Counter;

import java.awt.image.BufferedImage;

public class GraveyardBoneCounter extends Counter
{
	private final MageTrainingArenaPlugin plugin;

	public GraveyardBoneCounter(BufferedImage image, MageTrainingArenaPlugin plugin)
	{
		super(image, plugin, String.valueOf(plugin.getTotalFruitFromBones()));
		this.plugin = plugin;
	}

	@Override
	public String getText()
	{
		return String.valueOf(plugin.getTotalFruitFromBones());
	}

	@Override
	public String getTooltip()
	{
		return String.format("Fruit from bones: " + plugin.getTotalFruitFromBones());
	}
}
