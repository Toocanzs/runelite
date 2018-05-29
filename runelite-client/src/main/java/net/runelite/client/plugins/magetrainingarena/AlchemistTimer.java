package net.runelite.client.plugins.magetrainingarena;

import net.runelite.api.Client;
import net.runelite.api.widgets.Widget;
import net.runelite.api.widgets.WidgetID;
import net.runelite.client.ui.overlay.Overlay;
import net.runelite.client.ui.overlay.OverlayLayer;
import net.runelite.client.ui.overlay.OverlayPosition;
import net.runelite.client.ui.overlay.OverlayPriority;

import java.awt.Color;
import java.awt.Dimension;
import java.awt.Graphics2D;
import java.awt.Rectangle;

public class AlchemistTimer extends Overlay
{
	private final Client client;
	private final MageTrainingArenaPlugin plugin;

	AlchemistTimer(Client client, MageTrainingArenaPlugin plugin)
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

		Widget alchemsitWidget = client.getWidget(WidgetID.MAGE_TRAINING_ARENA_ALCHEMIST_GROUP_ID,0);

		if(alchemsitWidget != null && !alchemsitWidget.isHidden())
		{
			Rectangle bounds = alchemsitWidget.getBounds();

			final int width = 165;
			final int height = 8;

			float percent = 1-(plugin.getElapsedTicks()/70.0f);

			graphics.setColor(Color.black);
			graphics.fillRect(((int)(bounds.getX() + bounds.getWidth()) - width), (int)(bounds.getY() + bounds.getHeight()), width ,height);

			graphics.setColor(Color.GREEN);
			graphics.fillRect(((int)(bounds.getX() + bounds.getWidth()) - width), (int)(bounds.getY() + bounds.getHeight()), width - (int)(percent*width) ,height);
		}
		return null;
	}
}