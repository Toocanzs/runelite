/*
 * Copyright (c) 2018, Adam <Adam@sigterm.info>
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
package net.runelite.client.plugins.gpu;

import com.google.common.primitives.Ints;
import com.google.inject.Provides;
import java.awt.Canvas;
import java.awt.Dimension;
import java.awt.GraphicsConfiguration;
import java.awt.Image;
import java.awt.geom.AffineTransform;
import java.awt.image.BufferedImage;
import java.awt.image.DataBufferInt;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.nio.ShortBuffer;
import java.util.Random;
import javax.annotation.Nonnull;
import javax.inject.Inject;
import javax.swing.SwingUtilities;
import lombok.extern.slf4j.Slf4j;
import net.runelite.api.BufferProvider;
import net.runelite.api.Client;
import net.runelite.api.Constants;
import net.runelite.api.GameState;
import net.runelite.api.Model;
import net.runelite.api.Perspective;
import net.runelite.api.Renderable;
import net.runelite.api.Scene;
import net.runelite.api.SceneTileModel;
import net.runelite.api.SceneTilePaint;
import net.runelite.api.Texture;
import net.runelite.api.TextureProvider;
import net.runelite.api.events.GameStateChanged;
import net.runelite.api.hooks.DrawCallbacks;
import net.runelite.client.callback.ClientThread;
import net.runelite.client.config.ConfigManager;
import net.runelite.client.eventbus.Subscribe;
import net.runelite.client.events.ConfigChanged;
import net.runelite.client.plugins.Plugin;
import net.runelite.client.plugins.PluginDescriptor;
import net.runelite.client.plugins.PluginInstantiationException;
import net.runelite.client.plugins.PluginManager;
import net.runelite.client.plugins.gpu.config.AntiAliasingMode;
import net.runelite.client.plugins.gpu.config.UIScalingMode;
import net.runelite.client.plugins.gpu.template.Template;
import net.runelite.client.ui.ClientUI;
import net.runelite.client.ui.DrawManager;
import net.runelite.client.util.OSType;
import net.runelite.rlawt.AWTContext;
import org.lwjgl.opencl.CL10;
import org.lwjgl.opencl.CL10GL;
import org.lwjgl.opencl.CL12;
import org.lwjgl.opengl.*;
import org.lwjgl.system.Callback;
import org.lwjgl.system.Configuration;

@PluginDescriptor(
	name = "GPU",
	description = "Utilizes the GPU",
	enabledByDefault = false,
	tags = {"fog", "draw distance"},
	loadInSafeMode = false
)
@Slf4j
public class GpuPlugin extends Plugin implements DrawCallbacks
{
	// This is the maximum number of triangles the compute shaders support
	static final int MAX_TRIANGLE = 6144;
	static final int SMALL_TRIANGLE_COUNT = 512;
	private static final int FLAG_SCENE_BUFFER = Integer.MIN_VALUE;
	private static final int DEFAULT_DISTANCE = 25;
	static final int MAX_DISTANCE = 184;
	static final int MAX_FOG_DEPTH = 100;
	static final int SCENE_OFFSET = (Constants.EXTENDED_SCENE_SIZE - Constants.SCENE_SIZE) / 2; // offset for sxy -> msxy
	private static final int GROUND_MIN_Y = 350; // how far below the ground models extend

	@Inject
	private Client client;

	@Inject
	private ClientUI clientUI;

	@Inject
	private OpenCLManager openCLManager;

	@Inject
	private ClientThread clientThread;

	@Inject
	private GpuPluginConfig config;

	@Inject
	private TextureManager textureManager;

	@Inject
	private SceneUploader sceneUploader;

	@Inject
	private DrawManager drawManager;

	@Inject
	private PluginManager pluginManager;

	enum ComputeMode
	{
		NONE,
		OPENGL,
		OPENCL
	}

	private ComputeMode computeMode = ComputeMode.NONE;

	private Canvas canvas;
	private AWTContext awtContext;
	private Callback debugCallback;

	private GLCapabilities glCapabilities;

	static final String LINUX_VERSION_HEADER =
		"#version 420\n" +
			"#extension GL_ARB_compute_shader : require\n" +
			"#extension GL_ARB_shader_storage_buffer_object : require\n" +
			"#extension GL_ARB_explicit_attrib_location : require\n";
	static final String WINDOWS_VERSION_HEADER = "#version 430\n";

	static final Shader PROGRAM = new Shader()
		.add(GL43C.GL_VERTEX_SHADER, "vert.glsl")
		.add(GL43C.GL_GEOMETRY_SHADER, "geom.glsl")
		.add(GL43C.GL_FRAGMENT_SHADER, "frag.glsl");

	static final Shader COMPUTE_PROGRAM = new Shader()
		.add(GL43C.GL_COMPUTE_SHADER, "comp.glsl");

	static final Shader SMALL_COMPUTE_PROGRAM = new Shader()
		.add(GL43C.GL_COMPUTE_SHADER, "comp.glsl");

	static final Shader UNORDERED_COMPUTE_PROGRAM = new Shader()
		.add(GL43C.GL_COMPUTE_SHADER, "comp_unordered.glsl");

	static final Shader UI_PROGRAM = new Shader()
		.add(GL43C.GL_VERTEX_SHADER, "vertui.glsl")
		.add(GL43C.GL_FRAGMENT_SHADER, "fragui.glsl");

	static final Shader BITONIC_SORT_PROGRAM = new Shader()
			.add(GL43C.GL_COMPUTE_SHADER, "raytracing/sorts/bitonic/bitonic_sort.glsl");
	static final Shader BITONIC_SETUP_PROGRAM = new Shader()
			.add(GL43C.GL_COMPUTE_SHADER, "raytracing/sorts/bitonic/setup_keys_and_padding.glsl");

	static final Shader RADIX_TEST_PROGRAM = new Shader()
			.add(GL43C.GL_COMPUTE_SHADER, "raytracing/sorts/radix/radix_sort.glsl");
	static final Shader RADIX_COUNT_DIGITS_PROGRAM = new Shader()
			.add(GL43C.GL_COMPUTE_SHADER, "raytracing/sorts/radix/count_digits.glsl");
	static final Shader RADIX_COMPUTE_DIGIT_START_INDICES_PROGRAM = new Shader()
			.add(GL43C.GL_COMPUTE_SHADER, "raytracing/sorts/radix/compute_digit_start_indices.glsl");
	static final Shader MIN_MAX_PROGRAM = new Shader()
			.add(GL43C.GL_COMPUTE_SHADER, "raytracing/calculate_min_max.glsl");
	static final Shader MIN_MAX_SETUP_PROGRAM = new Shader()
			.add(GL43C.GL_COMPUTE_SHADER, "raytracing/init_min_max.glsl");
	static int glMinMaxBuffer;

	static final int radixWorkGroupSize = 512;
	// NOTE: For whatever reason, 4 bits per pass is faster than 8.
	// I've read multiple accounts of 8 bits per pass being faster for other people so unsure what the issue is here, although it's plenty fast already
	static final int radixBitsPerPass = 4;
	static final int radixNumPasses = 32 / radixBitsPerPass;
	static final int radixNumBuckets = 1 << radixBitsPerPass;


	private int glProgram;
	private int glComputeProgram;
	private int glSmallComputeProgram;
	private int glUnorderedComputeProgram;
	private int glBitonicSortProgram;
	private int glBitonicSetupProgram;
	private int glRadixCountDigitsProgram;
	private int glRadixComputeStartIndices;
	private int glMinMaxProgram;
	private int glMinMaxSetupProgram;
	private int glRadixSortProgram;
	private int glUiProgram;

	private int vaoCompute;
	private int vaoTemp;

	private int interfaceTexture;
	private int interfacePbo;

	private int vaoUiHandle;
	private int vboUiHandle;

	private int fboSceneHandle;
	private int rboSceneHandle;

	private final GLBuffer sceneVertexBuffer = new GLBuffer("scene vertex buffer");
	private final GLBuffer sceneUvBuffer = new GLBuffer("scene tex buffer");
	private final GLBuffer tmpVertexBuffer = new GLBuffer("tmp vertex buffer");
	private final GLBuffer tmpUvBuffer = new GLBuffer("tmp tex buffer");
	private final GLBuffer tmpModelBufferLarge = new GLBuffer("model buffer large");
	private final GLBuffer tmpModelBufferSmall = new GLBuffer("model buffer small");
	private final GLBuffer tmpModelBufferUnordered = new GLBuffer("model buffer unordered");
	private final GLBuffer tmpOutBuffer = new GLBuffer("out vertex buffer");
	private final GLBuffer mortonKeyValueBuffer = new GLBuffer("morton key value buffer");
	private final GLBuffer tmpMortonKeyValueBuffer = new GLBuffer("temp morton key value buffer");
	private final GLBuffer radixControlBuffer = new GLBuffer("radix control buffer");
	private final GLBuffer radixDigitStartIndicesBuffer = new GLBuffer("radix digit start indices buffer");
	private final GLBuffer tmpOutUvBuffer = new GLBuffer("out tex buffer");

	private final int[] radixTimingQueries = new int[4];

	private int textureArrayId;
	private int tileHeightTex;

	private final GLBuffer uniformBuffer = new GLBuffer("uniform buffer");

	private GpuIntBuffer vertexBuffer;
	private GpuFloatBuffer uvBuffer;

	private GpuIntBuffer modelBufferUnordered;
	private GpuIntBuffer modelBufferSmall;
	private GpuIntBuffer modelBuffer;

	private int unorderedModels;

	/**
	 * number of models in small buffer
	 */
	private int smallModels;

	/**
	 * number of models in large buffer
	 */
	private int largeModels;

	/**
	 * offset in the target buffer for model
	 */
	private int targetBufferOffset;

	/**
	 * offset into the temporary scene vertex buffer
	 */
	private int tempOffset;

	/**
	 * offset into the temporary scene uv buffer
	 */
	private int tempUvOffset;

	private int lastCanvasWidth;
	private int lastCanvasHeight;
	private int lastStretchedCanvasWidth;
	private int lastStretchedCanvasHeight;
	private AntiAliasingMode lastAntiAliasingMode;
	private int lastAnisotropicFilteringLevel = -1;

	private double cameraX, cameraY, cameraZ;
	private double cameraYaw, cameraPitch;

	private int viewportOffsetX;
	private int viewportOffsetY;

	// Uniforms
	private int uniColorBlindMode;
	private int uniUiColorBlindMode;
	private int uniUseFog;
	private int uniFogColor;
	private int uniFogDepth;
	private int uniDrawDistance;
	private int uniExpandedMapLoadingChunks;
	private int uniProjectionMatrix;
	private int uniBrightness;
	private int uniTex;
	private int uniTexSamplingMode;
	private int uniTexSourceDimensions;
	private int uniTexTargetDimensions;
	private int uniUiAlphaOverlay;
	private int uniUiViewMatrix;
	private int uniUiVertexCount;
	private int uniUiBrightness;
	private int uniUiAspectScaling;
	private int uniUiCameraPosition;
	private int uniTextures;
	private int uniTextureAnimations;
	private int uniBlockSmall;
	private int uniBlockLarge;
	private int uniBlockMain;
	private int uniSmoothBanding;
	private int uniTextureLightMode;
	private int uniTick;
	private int uniRadixDigitCountNumItems;
	private int uniRadixNumItems;
	private int uniRadixPassNumber;
	private int uniMinMaxNumItems;

	private boolean lwjglInitted = false;

	private int sceneId;
	private int nextSceneId;
	private GpuIntBuffer nextSceneVertexBuffer;
	private GpuFloatBuffer nextSceneTexBuffer;

	@Override
	protected void startUp()
	{
		clientThread.invoke(() ->
		{
			try
			{
				fboSceneHandle = rboSceneHandle = -1; // AA FBO
				targetBufferOffset = 0;
				unorderedModels = smallModels = largeModels = 0;

				AWTContext.loadNatives();

				canvas = client.getCanvas();

				synchronized (canvas.getTreeLock())
				{
					if (!canvas.isValid())
					{
						return false;
					}

					awtContext = new AWTContext(canvas);
					awtContext.configurePixelFormat(0, 0, 0);
				}

				awtContext.createGLContext();

				canvas.setIgnoreRepaint(true);

				computeMode = config.useComputeShaders()
					? (OSType.getOSType() == OSType.MacOS ? ComputeMode.OPENCL : ComputeMode.OPENGL)
					: ComputeMode.NONE;

				// lwjgl defaults to lwjgl- + user.name, but this breaks if the username would cause an invalid path
				// to be created.
				Configuration.SHARED_LIBRARY_EXTRACT_DIRECTORY.set("lwjgl-rl");

				glCapabilities = GL.createCapabilities();

				log.info("Using device: {}", GL43C.glGetString(GL43C.GL_RENDERER));
				log.info("Using driver: {}", GL43C.glGetString(GL43C.GL_VERSION));

				if (!glCapabilities.OpenGL31)
				{
					throw new RuntimeException("OpenGL 3.1 is required but not available");
				}

				if (!glCapabilities.OpenGL43 && computeMode == ComputeMode.OPENGL)
				{
					log.info("disabling compute shaders because OpenGL 4.3 is not available");
					computeMode = ComputeMode.NONE;
				}

				if (computeMode == ComputeMode.NONE)
				{
					sceneUploader.initSortingBuffers();
				}

				lwjglInitted = true;

				checkGLErrors();
				if (log.isDebugEnabled() && glCapabilities.glDebugMessageControl != 0)
				{
					debugCallback = GLUtil.setupDebugMessageCallback();
					if (debugCallback != null)
					{
						//	GLDebugEvent[ id 0x20071
						//		type Warning: generic
						//		severity Unknown (0x826b)
						//		source GL API
						//		msg Buffer detailed info: Buffer object 11 (bound to GL_ARRAY_BUFFER_ARB, and GL_SHADER_STORAGE_BUFFER (4), usage hint is GL_STREAM_DRAW) will use VIDEO memory as the source for buffer object operations.
						GL43C.glDebugMessageControl(GL43C.GL_DEBUG_SOURCE_API, GL43C.GL_DEBUG_TYPE_OTHER,
							GL43C.GL_DONT_CARE, 0x20071, false);

						//	GLDebugMessageHandler: GLDebugEvent[ id 0x20052
						//		type Warning: implementation dependent performance
						//		severity Medium: Severe performance/deprecation/other warnings
						//		source GL API
						//		msg Pixel-path performance warning: Pixel transfer is synchronized with 3D rendering.
						GL43C.glDebugMessageControl(GL43C.GL_DEBUG_SOURCE_API, GL43C.GL_DEBUG_TYPE_PERFORMANCE,
							GL43C.GL_DONT_CARE, 0x20052, false);
					}
				}

				vertexBuffer = new GpuIntBuffer();
				uvBuffer = new GpuFloatBuffer();

				modelBufferUnordered = new GpuIntBuffer();
				modelBufferSmall = new GpuIntBuffer();
				modelBuffer = new GpuIntBuffer();

				setupSyncMode();

				initBuffers();
				initVao();
				try
				{
					initProgram();
				}
				catch (ShaderException ex)
				{
					throw new RuntimeException(ex);
				}
				initInterfaceTexture();
				initUniformBuffer();

				client.setDrawCallbacks(this);
				client.setGpuFlags(DrawCallbacks.GPU
					| (computeMode == ComputeMode.NONE ? 0 : DrawCallbacks.HILLSKEW)
				);
				client.setExpandedMapLoading(config.expandedMapLoadingChunks());

				// force rebuild of main buffer provider to enable alpha channel
				client.resizeCanvas();

				lastCanvasWidth = lastCanvasHeight = -1;
				lastStretchedCanvasWidth = lastStretchedCanvasHeight = -1;
				lastAntiAliasingMode = null;

				textureArrayId = -1;

				if (client.getGameState() == GameState.LOGGED_IN)
				{
					Scene scene = client.getScene();
					loadScene(scene);
					swapScene(scene);
				}

				checkGLErrors();
			}
			catch (Throwable e)
			{
				log.error("Error starting GPU plugin", e);

				SwingUtilities.invokeLater(() ->
				{
					try
					{
						pluginManager.setPluginEnabled(this, false);
						pluginManager.stopPlugin(this);
					}
					catch (PluginInstantiationException ex)
					{
						log.error("error stopping plugin", ex);
					}
				});

				shutDown();
			}
			return true;
		});
	}

	@Override
	protected void shutDown()
	{
		clientThread.invoke(() ->
		{
			client.setGpuFlags(0);
			client.setDrawCallbacks(null);
			client.setUnlockedFps(false);
			client.setExpandedMapLoading(0);

			sceneUploader.releaseSortingBuffers();

			if (lwjglInitted)
			{
				if (textureArrayId != -1)
				{
					textureManager.freeTextureArray(textureArrayId);
					textureArrayId = -1;
				}

				if (tileHeightTex != 0)
				{
					GL43C.glDeleteTextures(tileHeightTex);
					tileHeightTex = 0;
				}

				destroyGlBuffer(uniformBuffer);

				shutdownInterfaceTexture();
				shutdownProgram();
				shutdownVao();
				shutdownBuffers();
				shutdownAAFbo();
			}

			// this must shutdown after the clgl buffers are freed
			openCLManager.cleanup();

			if (awtContext != null)
			{
				awtContext.destroy();
				awtContext = null;
			}

			if (debugCallback != null)
			{
				debugCallback.free();
				debugCallback = null;
			}

			glCapabilities = null;

			vertexBuffer = null;
			uvBuffer = null;

			modelBufferSmall = null;
			modelBuffer = null;
			modelBufferUnordered = null;

			lastAnisotropicFilteringLevel = -1;

			// force main buffer provider rebuild to turn off alpha channel
			client.resizeCanvas();
		});
	}

	@Provides
	GpuPluginConfig provideConfig(ConfigManager configManager)
	{
		return configManager.getConfig(GpuPluginConfig.class);
	}

	@Subscribe
	public void onConfigChanged(ConfigChanged configChanged)
	{
		if (configChanged.getGroup().equals(GpuPluginConfig.GROUP))
		{
			if (configChanged.getKey().equals("unlockFps")
				|| configChanged.getKey().equals("vsyncMode")
				|| configChanged.getKey().equals("fpsTarget"))
			{
				log.debug("Rebuilding sync mode");
				clientThread.invokeLater(this::setupSyncMode);
			}
			else if (configChanged.getKey().equals("expandedMapLoadingChunks"))
			{
				clientThread.invokeLater(() ->
				{
					client.setExpandedMapLoading(config.expandedMapLoadingChunks());
					if (client.getGameState() == GameState.LOGGED_IN)
					{
						client.setGameState(GameState.LOADING);
					}
				});
			}
		}
	}

	private void setupSyncMode()
	{
		final boolean unlockFps = config.unlockFps();
		client.setUnlockedFps(unlockFps);

		// Without unlocked fps, the client manages sync on its 20ms timer
		GpuPluginConfig.SyncMode syncMode = unlockFps
			? this.config.syncMode()
			: GpuPluginConfig.SyncMode.OFF;

		int swapInterval = 0;
		switch (syncMode)
		{
			case ON:
				swapInterval = 1;
				break;
			case OFF:
				swapInterval = 0;
				break;
			case ADAPTIVE:
				swapInterval = -1;
				break;
		}

		int actualSwapInterval = awtContext.setSwapInterval(swapInterval);
		if (actualSwapInterval != swapInterval)
		{
			log.info("unsupported swap interval {}, got {}", swapInterval, actualSwapInterval);
		}

		client.setUnlockedFpsTarget(actualSwapInterval == 0 ? config.fpsTarget() : 0);
		checkGLErrors();
	}

	private Template createTemplate(int threadCount, int facesPerThread)
	{
		String versionHeader = OSType.getOSType() == OSType.Linux ? LINUX_VERSION_HEADER : WINDOWS_VERSION_HEADER;
		Template template = new Template();
		template.add(key ->
		{
			if ("version_header".equals(key))
			{
				return versionHeader;
			}
			if ("thread_config".equals(key))
			{
				return "#define THREAD_COUNT " + threadCount + "\n" +
					"#define FACES_PER_THREAD " + facesPerThread + "\n";
			}
			return null;
		});
		template.addInclude(GpuPlugin.class);
		return template;
	}

	private Template createRadixTemplate(int bitsPerPass, int workGroupSizeX)
	{
		final int numBuckets = (1 << bitsPerPass);
		final int numPasses = 32/bitsPerPass;
		String versionHeader = OSType.getOSType() == OSType.Linux ? LINUX_VERSION_HEADER : WINDOWS_VERSION_HEADER;

		Template template = new Template();
		template.add(key ->
		{
			if ("version_header".equals(key))
			{
				return versionHeader;
			}
			if ("bits_per_pass".equals(key))
			{
				return "#define BITS_PER_PASS " + bitsPerPass + "\n";
			}
			if ("thread_count".equals(key))
			{
				return "#define THREAD_COUNT " + workGroupSizeX + "\n";
			}
			if ("num_buckets".equals(key))
			{
				return "#define NUM_BUCKETS " + numBuckets + "\n";
			}
			if ("num_passes".equals(key))
			{
				return "#define NUM_PASSES " + numPasses + "\n";
			}
			return null;
		});
		template.addInclude(GpuPlugin.class);
		return template;
	}

	private void initProgram() throws ShaderException
	{
		Template template = createTemplate(-1, -1);
		glProgram = PROGRAM.compile(template);
		glUiProgram = UI_PROGRAM.compile(template);

		if (computeMode == ComputeMode.OPENGL)
		{
			glComputeProgram = COMPUTE_PROGRAM.compile(createTemplate(1024, 6));
			glSmallComputeProgram = SMALL_COMPUTE_PROGRAM.compile(createTemplate(512, 1));
			glUnorderedComputeProgram = UNORDERED_COMPUTE_PROGRAM.compile(template);

			glRadixSortProgram = RADIX_TEST_PROGRAM.compile(createRadixTemplate(radixBitsPerPass, radixWorkGroupSize));
			glRadixCountDigitsProgram = RADIX_COUNT_DIGITS_PROGRAM.compile(createRadixTemplate(radixBitsPerPass, radixWorkGroupSize));
			glRadixComputeStartIndices = RADIX_COMPUTE_DIGIT_START_INDICES_PROGRAM.compile(createRadixTemplate(radixBitsPerPass, radixNumBuckets)); // Thread config is not used here

			glMinMaxProgram = MIN_MAX_PROGRAM.compile(createTemplate(radixWorkGroupSize,-1));
			glMinMaxBuffer = GL43C.glGenBuffers();
			GL43C.glBindBuffer(GL43C.GL_SHADER_STORAGE_BUFFER, glMinMaxBuffer);
			GL43C.glBufferData(GL43C.GL_SHADER_STORAGE_BUFFER, 6*4, GL43C.GL_DYNAMIC_DRAW); // NOTE: 6 ints for min x/y/z and max x/y/z, size = 4 bytes each

			glMinMaxSetupProgram = MIN_MAX_SETUP_PROGRAM.compile(createTemplate(-1,-1));

			checkGLErrors();
		}
		else if (computeMode == ComputeMode.OPENCL)
		{
			openCLManager.init(awtContext);
		}

		initUniforms();
	}

	private void initUniforms()
	{
		uniProjectionMatrix = GL43C.glGetUniformLocation(glProgram, "projectionMatrix");
		uniBrightness = GL43C.glGetUniformLocation(glProgram, "brightness");
		uniSmoothBanding = GL43C.glGetUniformLocation(glProgram, "smoothBanding");
		uniUseFog = GL43C.glGetUniformLocation(glProgram, "useFog");
		uniFogColor = GL43C.glGetUniformLocation(glProgram, "fogColor");
		uniFogDepth = GL43C.glGetUniformLocation(glProgram, "fogDepth");
		uniDrawDistance = GL43C.glGetUniformLocation(glProgram, "drawDistance");
		uniExpandedMapLoadingChunks = GL43C.glGetUniformLocation(glProgram, "expandedMapLoadingChunks");
		uniColorBlindMode = GL43C.glGetUniformLocation(glProgram, "colorBlindMode");
		uniTextureLightMode = GL43C.glGetUniformLocation(glProgram, "textureLightMode");
		uniTick = GL43C.glGetUniformLocation(glProgram, "tick");
		uniBlockMain = GL43C.glGetUniformBlockIndex(glProgram, "uniforms");
		uniTextures = GL43C.glGetUniformLocation(glProgram, "textures");
		uniTextureAnimations = GL43C.glGetUniformLocation(glProgram, "textureAnimations");

		uniTex = GL43C.glGetUniformLocation(glUiProgram, "tex");
		uniTexSamplingMode = GL43C.glGetUniformLocation(glUiProgram, "samplingMode");
		uniTexTargetDimensions = GL43C.glGetUniformLocation(glUiProgram, "targetDimensions");
		uniTexSourceDimensions = GL43C.glGetUniformLocation(glUiProgram, "sourceDimensions");
		uniUiColorBlindMode = GL43C.glGetUniformLocation(glUiProgram, "colorBlindMode");
		uniUiAlphaOverlay = GL43C.glGetUniformLocation(glUiProgram, "alphaOverlay");

		uniUiViewMatrix = GL43C.glGetUniformLocation(glUiProgram, "viewMatrix");

		uniUiVertexCount = GL43C.glGetUniformLocation(glUiProgram, "vertexCount");
		uniUiBrightness = GL43C.glGetUniformLocation(glUiProgram, "brightness");
		uniUiAspectScaling = GL43C.glGetUniformLocation(glUiProgram, "aspectScaling");
		uniUiCameraPosition = GL43C.glGetUniformLocation(glUiProgram, "cameraPosition");

		uniRadixDigitCountNumItems = GL43C.glGetUniformLocation(glRadixCountDigitsProgram, "num_items");

		uniRadixNumItems = GL43C.glGetUniformLocation(glRadixSortProgram, "num_items");
		uniRadixPassNumber = GL43C.glGetUniformLocation(glRadixSortProgram, "pass_number");

		uniMinMaxNumItems = GL43C.glGetUniformLocation(glMinMaxProgram, "num_items");

		if (computeMode == ComputeMode.OPENGL)
		{
			uniBlockSmall = GL43C.glGetUniformBlockIndex(glSmallComputeProgram, "uniforms");
			uniBlockLarge = GL43C.glGetUniformBlockIndex(glComputeProgram, "uniforms");
		}
	}

	private void shutdownProgram()
	{
		GL43C.glDeleteProgram(glProgram);
		glProgram = -1;

		GL43C.glDeleteProgram(glComputeProgram);
		glComputeProgram = -1;

		GL43C.glDeleteProgram(glSmallComputeProgram);
		glSmallComputeProgram = -1;

		GL43C.glDeleteProgram(glUnorderedComputeProgram);
		glUnorderedComputeProgram = -1;

		GL43C.glDeleteProgram(glBitonicSortProgram);
		glBitonicSortProgram = -1;

		GL43C.glDeleteProgram(glRadixSortProgram);
		glRadixSortProgram = -1;

		GL43C.glDeleteProgram(glRadixCountDigitsProgram);
		glRadixCountDigitsProgram = -1;

		GL43C.glDeleteProgram(glRadixComputeStartIndices);
		glRadixComputeStartIndices = -1;

		GL43C.glDeleteProgram(glMinMaxProgram);
		glMinMaxProgram = -1;
		GL43C.glDeleteBuffers(glMinMaxBuffer);

		GL43C.glDeleteProgram(glMinMaxSetupProgram);
		glMinMaxSetupProgram = -1;

		GL43C.glDeleteProgram(glBitonicSetupProgram);
		glBitonicSetupProgram = -1;

		GL43C.glDeleteProgram(glUiProgram);
		glUiProgram = -1;
	}

	private void initVao()
	{
		// Create compute VAO
		vaoCompute = GL43C.glGenVertexArrays();
		GL43C.glBindVertexArray(vaoCompute);

		GL43C.glEnableVertexAttribArray(0);
		GL43C.glBindBuffer(GL43C.GL_ARRAY_BUFFER, tmpOutBuffer.glBufferId);
		GL43C.glVertexAttribIPointer(0, 4, GL43C.GL_INT, 0, 0);

		GL43C.glEnableVertexAttribArray(1);
		GL43C.glBindBuffer(GL43C.GL_ARRAY_BUFFER, tmpOutUvBuffer.glBufferId);
		GL43C.glVertexAttribPointer(1, 4, GL43C.GL_FLOAT, false, 0, 0);

		// Create temp VAO
		vaoTemp = GL43C.glGenVertexArrays();
		GL43C.glBindVertexArray(vaoTemp);

		GL43C.glEnableVertexAttribArray(0);
		GL43C.glBindBuffer(GL43C.GL_ARRAY_BUFFER, tmpVertexBuffer.glBufferId);
		GL43C.glVertexAttribIPointer(0, 4, GL43C.GL_INT, 0, 0);

		GL43C.glEnableVertexAttribArray(1);
		GL43C.glBindBuffer(GL43C.GL_ARRAY_BUFFER, tmpUvBuffer.glBufferId);
		GL43C.glVertexAttribPointer(1, 4, GL43C.GL_FLOAT, false, 0, 0);

		// Create UI VAO
		vaoUiHandle = GL43C.glGenVertexArrays();
		// Create UI buffer
		vboUiHandle = GL43C.glGenBuffers();
		GL43C.glBindVertexArray(vaoUiHandle);

		FloatBuffer vboUiBuf = GpuFloatBuffer.allocateDirect(5 * 4);
		vboUiBuf.put(new float[]{
			// positions     // texture coords
			1f, 1f, 0.0f, 1.0f, 0f, // top right
			1f, -1f, 0.0f, 1.0f, 1f, // bottom right
			-1f, -1f, 0.0f, 0.0f, 1f, // bottom left
			-1f, 1f, 0.0f, 0.0f, 0f  // top left
		});
		vboUiBuf.rewind();
		GL43C.glBindBuffer(GL43C.GL_ARRAY_BUFFER, vboUiHandle);
		GL43C.glBufferData(GL43C.GL_ARRAY_BUFFER, vboUiBuf, GL43C.GL_STATIC_DRAW);

		// position attribute
		GL43C.glVertexAttribPointer(0, 3, GL43C.GL_FLOAT, false, 5 * Float.BYTES, 0);
		GL43C.glEnableVertexAttribArray(0);

		// texture coord attribute
		GL43C.glVertexAttribPointer(1, 2, GL43C.GL_FLOAT, false, 5 * Float.BYTES, 3 * Float.BYTES);
		GL43C.glEnableVertexAttribArray(1);

		// unbind VBO
		GL43C.glBindBuffer(GL43C.GL_ARRAY_BUFFER, 0);
	}

	private void shutdownVao()
	{
		GL43C.glDeleteVertexArrays(vaoCompute);
		vaoCompute = -1;

		GL43C.glDeleteVertexArrays(vaoTemp);
		vaoTemp = -1;

		GL43C.glDeleteBuffers(vboUiHandle);
		vboUiHandle = -1;

		GL43C.glDeleteVertexArrays(vaoUiHandle);
		vaoUiHandle = -1;
	}

	private void initBuffers()
	{
		initGlBuffer(sceneVertexBuffer);
		initGlBuffer(sceneUvBuffer);
		initGlBuffer(tmpVertexBuffer);
		initGlBuffer(tmpUvBuffer);
		initGlBuffer(tmpModelBufferLarge);
		initGlBuffer(tmpModelBufferSmall);
		initGlBuffer(tmpModelBufferUnordered);
		initGlBuffer(tmpOutBuffer);
		initGlBuffer(mortonKeyValueBuffer);
		initGlBuffer(tmpMortonKeyValueBuffer);
		initGlBuffer(radixControlBuffer);
		initGlBuffer(radixDigitStartIndicesBuffer);
		initGlBuffer(tmpOutUvBuffer);

		GL43C.glGenQueries(radixTimingQueries); // TODO: Remove
	}

	private void initGlBuffer(GLBuffer glBuffer)
	{
		glBuffer.glBufferId = GL43C.glGenBuffers();
	}

	private void shutdownBuffers()
	{
		destroyGlBuffer(sceneVertexBuffer);
		destroyGlBuffer(sceneUvBuffer);

		destroyGlBuffer(tmpVertexBuffer);
		destroyGlBuffer(tmpUvBuffer);
		destroyGlBuffer(tmpModelBufferLarge);
		destroyGlBuffer(tmpModelBufferSmall);
		destroyGlBuffer(tmpModelBufferUnordered);
		destroyGlBuffer(tmpOutBuffer);
		destroyGlBuffer(mortonKeyValueBuffer);
		destroyGlBuffer(tmpMortonKeyValueBuffer);
		destroyGlBuffer(radixControlBuffer);
		destroyGlBuffer(radixDigitStartIndicesBuffer);
		destroyGlBuffer(tmpOutUvBuffer);
		GL43C.glDeleteQueries(radixTimingQueries);
	}

	private void destroyGlBuffer(GLBuffer glBuffer)
	{
		if (glBuffer.glBufferId != -1)
		{
			GL43C.glDeleteBuffers(glBuffer.glBufferId);
			glBuffer.glBufferId = -1;
		}
		glBuffer.size = -1;

		if (glBuffer.clBuffer != -1)
		{
			CL12.clReleaseMemObject(glBuffer.clBuffer);
			glBuffer.clBuffer = -1;
		}
	}

	private void initInterfaceTexture()
	{
		interfacePbo = GL43C.glGenBuffers();

		interfaceTexture = GL43C.glGenTextures();
		GL43C.glBindTexture(GL43C.GL_TEXTURE_2D, interfaceTexture);
		GL43C.glTexParameteri(GL43C.GL_TEXTURE_2D, GL43C.GL_TEXTURE_WRAP_S, GL43C.GL_CLAMP_TO_EDGE);
		GL43C.glTexParameteri(GL43C.GL_TEXTURE_2D, GL43C.GL_TEXTURE_WRAP_T, GL43C.GL_CLAMP_TO_EDGE);
		GL43C.glTexParameteri(GL43C.GL_TEXTURE_2D, GL43C.GL_TEXTURE_MIN_FILTER, GL43C.GL_LINEAR);
		GL43C.glTexParameteri(GL43C.GL_TEXTURE_2D, GL43C.GL_TEXTURE_MAG_FILTER, GL43C.GL_LINEAR);
		GL43C.glBindTexture(GL43C.GL_TEXTURE_2D, 0);
	}

	private void shutdownInterfaceTexture()
	{
		GL43C.glDeleteBuffers(interfacePbo);
		GL43C.glDeleteTextures(interfaceTexture);
		interfaceTexture = -1;
	}

	private void initUniformBuffer()
	{
		initGlBuffer(uniformBuffer);

		IntBuffer uniformBuf = GpuIntBuffer.allocateDirect(8 + 2048 * 4);
		uniformBuf.put(new int[8]); // uniform block
		final int[] pad = new int[2];
		for (int i = 0; i < 2048; i++)
		{
			uniformBuf.put(Perspective.SINE[i]);
			uniformBuf.put(Perspective.COSINE[i]);
			uniformBuf.put(pad); // ivec2 alignment in std140 is 16 bytes
		}
		uniformBuf.flip();

		updateBuffer(uniformBuffer, GL43C.GL_UNIFORM_BUFFER, uniformBuf, GL43C.GL_DYNAMIC_DRAW, CL12.CL_MEM_READ_ONLY);
		GL43C.glBindBuffer(GL43C.GL_UNIFORM_BUFFER, 0);
	}

	private void initAAFbo(int width, int height, int aaSamples)
	{
		if (OSType.getOSType() != OSType.MacOS)
		{
			final GraphicsConfiguration graphicsConfiguration = clientUI.getGraphicsConfiguration();
			final AffineTransform transform = graphicsConfiguration.getDefaultTransform();

			width = getScaledValue(transform.getScaleX(), width);
			height = getScaledValue(transform.getScaleY(), height);
		}

		// Create and bind the FBO
		fboSceneHandle = GL43C.glGenFramebuffers();
		GL43C.glBindFramebuffer(GL43C.GL_FRAMEBUFFER, fboSceneHandle);

		// Create color render buffer
		rboSceneHandle = GL43C.glGenRenderbuffers();
		GL43C.glBindRenderbuffer(GL43C.GL_RENDERBUFFER, rboSceneHandle);
		GL43C.glRenderbufferStorageMultisample(GL43C.GL_RENDERBUFFER, aaSamples, GL43C.GL_RGBA, width, height);
		GL43C.glFramebufferRenderbuffer(GL43C.GL_FRAMEBUFFER, GL43C.GL_COLOR_ATTACHMENT0, GL43C.GL_RENDERBUFFER, rboSceneHandle);

		int status = GL43C.glCheckFramebufferStatus(GL43C.GL_FRAMEBUFFER);
		if (status != GL43C.GL_FRAMEBUFFER_COMPLETE)
		{
			throw new RuntimeException("FBO is incomplete. status: " + status);
		}

		// Reset
		GL43C.glBindFramebuffer(GL43C.GL_FRAMEBUFFER, awtContext.getFramebuffer(false));
		GL43C.glBindRenderbuffer(GL43C.GL_RENDERBUFFER, 0);
	}

	private void shutdownAAFbo()
	{
		if (fboSceneHandle != -1)
		{
			GL43C.glDeleteFramebuffers(fboSceneHandle);
			fboSceneHandle = -1;
		}

		if (rboSceneHandle != -1)
		{
			GL43C.glDeleteRenderbuffers(rboSceneHandle);
			rboSceneHandle = -1;
		}
	}

	@Override
	public void drawScene(double cameraX, double cameraY, double cameraZ, double cameraPitch, double cameraYaw, int plane)
	{
		this.cameraX = cameraX;
		this.cameraY = cameraY;
		this.cameraZ = cameraZ;
		this.cameraPitch = cameraPitch;
		this.cameraYaw = cameraYaw;
		viewportOffsetX = client.getViewportXOffset();
		viewportOffsetY = client.getViewportYOffset();

		final Scene scene = client.getScene();
		scene.setDrawDistance(getDrawDistance());

		// Only reset the target buffer offset right before drawing the scene. That way if there are frames
		// after this that don't involve a scene draw, like during LOADING/HOPPING/CONNECTION_LOST, we can
		// still redraw the previous frame's scene to emulate the client behavior of not painting over the
		// viewport buffer.
		targetBufferOffset = 0;

		// UBO. Only the first 32 bytes get modified here, the rest is the constant sin/cos table.
		// We can reuse the vertex buffer since it isn't used yet.
		vertexBuffer.clear();
		vertexBuffer.ensureCapacity(32);
		IntBuffer uniformBuf = vertexBuffer.getBuffer();
		uniformBuf
			.put(Float.floatToIntBits((float) cameraYaw))
			.put(Float.floatToIntBits((float) cameraPitch))
			.put(client.getCenterX())
			.put(client.getCenterY())
			.put(client.getScale())
			.put(Float.floatToIntBits((float) cameraX))
			.put(Float.floatToIntBits((float) cameraY))
			.put(Float.floatToIntBits((float) cameraZ));
		uniformBuf.flip();

		GL43C.glBindBuffer(GL43C.GL_UNIFORM_BUFFER, uniformBuffer.glBufferId);
		GL43C.glBufferSubData(GL43C.GL_UNIFORM_BUFFER, 0, uniformBuf);
		GL43C.glBindBuffer(GL43C.GL_UNIFORM_BUFFER, 0);

		GL43C.glBindBufferBase(GL43C.GL_UNIFORM_BUFFER, 0, uniformBuffer.glBufferId);
		uniformBuf.clear();

		checkGLErrors();
	}

	@Override
	public void postDrawScene()
	{
		if (computeMode == ComputeMode.NONE)
		{
			// Upload buffers
			vertexBuffer.flip();
			uvBuffer.flip();

			IntBuffer vertexBuffer = this.vertexBuffer.getBuffer();
			FloatBuffer uvBuffer = this.uvBuffer.getBuffer();

			updateBuffer(tmpVertexBuffer, GL43C.GL_ARRAY_BUFFER, vertexBuffer, GL43C.GL_DYNAMIC_DRAW, 0L);
			updateBuffer(tmpUvBuffer, GL43C.GL_ARRAY_BUFFER, uvBuffer, GL43C.GL_DYNAMIC_DRAW, 0L);

			checkGLErrors();
			return;
		}

		// Upload buffers
		vertexBuffer.flip();
		uvBuffer.flip();
		modelBuffer.flip();
		modelBufferSmall.flip();
		modelBufferUnordered.flip();

		IntBuffer vertexBuffer = this.vertexBuffer.getBuffer();
		FloatBuffer uvBuffer = this.uvBuffer.getBuffer();
		IntBuffer modelBuffer = this.modelBuffer.getBuffer();
		IntBuffer modelBufferSmall = this.modelBufferSmall.getBuffer();
		IntBuffer modelBufferUnordered = this.modelBufferUnordered.getBuffer();

		// temp buffers
		updateBuffer(tmpVertexBuffer, GL43C.GL_ARRAY_BUFFER, vertexBuffer, GL43C.GL_DYNAMIC_DRAW, CL12.CL_MEM_READ_ONLY);
		updateBuffer(tmpUvBuffer, GL43C.GL_ARRAY_BUFFER, uvBuffer, GL43C.GL_DYNAMIC_DRAW, CL12.CL_MEM_READ_ONLY);

		// model buffers
		updateBuffer(tmpModelBufferLarge, GL43C.GL_ARRAY_BUFFER, modelBuffer, GL43C.GL_DYNAMIC_DRAW, CL12.CL_MEM_READ_ONLY);
		updateBuffer(tmpModelBufferSmall, GL43C.GL_ARRAY_BUFFER, modelBufferSmall, GL43C.GL_DYNAMIC_DRAW, CL12.CL_MEM_READ_ONLY);
		updateBuffer(tmpModelBufferUnordered, GL43C.GL_ARRAY_BUFFER, modelBufferUnordered, GL43C.GL_DYNAMIC_DRAW, CL12.CL_MEM_READ_ONLY);

		// Output buffers
		updateBuffer(tmpOutBuffer,
			GL43C.GL_ARRAY_BUFFER,
			targetBufferOffset * 16, // each element is an ivec4, which is 16 bytes
			GL43C.GL_STREAM_DRAW,
			CL12.CL_MEM_WRITE_ONLY);
		updateBuffer(tmpOutUvBuffer,
			GL43C.GL_ARRAY_BUFFER,
			targetBufferOffset * 16, // each element is a vec4, which is 16 bytes
			GL43C.GL_STREAM_DRAW,
			CL12.CL_MEM_WRITE_ONLY);

		if (computeMode == ComputeMode.OPENCL)
		{
			// The docs for clEnqueueAcquireGLObjects say all pending GL operations must be completed before calling
			// clEnqueueAcquireGLObjects, and recommends calling glFinish() as the only portable way to do that.
			// However no issues have been observed from not calling it, and so will leave disabled for now.
			// GL43C.glFinish();

			openCLManager.compute(
				unorderedModels, smallModels, largeModels,
				sceneVertexBuffer, sceneUvBuffer,
				tmpVertexBuffer, tmpUvBuffer,
				tmpModelBufferUnordered, tmpModelBufferSmall, tmpModelBufferLarge,
				tmpOutBuffer, tmpOutUvBuffer,
				uniformBuffer);

			checkGLErrors();
			return;
		}

		/*
		 * Compute is split into three separate programs: 'unordered', 'small', and 'large'
		 * to save on GPU resources. Small will sort <= 512 faces, large will do <= 6144.
		 */

		// Bind UBO to compute programs
		GL43C.glUniformBlockBinding(glSmallComputeProgram, uniBlockSmall, 0);
		GL43C.glUniformBlockBinding(glComputeProgram, uniBlockLarge, 0);

		// unordered
		GL43C.glUseProgram(glUnorderedComputeProgram);

		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, tmpModelBufferUnordered.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 1, sceneVertexBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 2, tmpVertexBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 3, tmpOutBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 4, tmpOutUvBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 5, sceneUvBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 6, tmpUvBuffer.glBufferId);

		GL43C.glDispatchCompute(unorderedModels, 1, 1);

		// small
		GL43C.glUseProgram(glSmallComputeProgram);

		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, tmpModelBufferSmall.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 1, sceneVertexBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 2, tmpVertexBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 3, tmpOutBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 4, tmpOutUvBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 5, sceneUvBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 6, tmpUvBuffer.glBufferId);

		GL43C.glDispatchCompute(smallModels, 1, 1);

		// large
		GL43C.glUseProgram(glComputeProgram);

		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, tmpModelBufferLarge.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 1, sceneVertexBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 2, tmpVertexBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 3, tmpOutBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 4, tmpOutUvBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 5, sceneUvBuffer.glBufferId);
		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 6, tmpUvBuffer.glBufferId);

		GL43C.glDispatchCompute(largeModels, 1, 1);

		buildBVH();

		checkGLErrors();
	}

	private void buildBVH() {
		if (computeMode == ComputeMode.OPENGL) {
			// Clear min/max buffer to max/min value for int so future atomic min/max will calculate the actual min/max
			GL43C.glUseProgram(glMinMaxSetupProgram);
			GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, glMinMaxBuffer);
			GL43C.glDispatchCompute(1, 1, 1);

			// Barrier to wait for writes from previous compute shaders and the min max setup
			GL43C.glMemoryBarrier(GL43C.GL_SHADER_STORAGE_BARRIER_BIT);

			final int numVertices = targetBufferOffset;
			assert numVertices % 3 == 0 : "numVertices is not a multiple of three";
			final int numTris = numVertices/3;
			final int numBlocksVertices = (numVertices + radixWorkGroupSize - 1) / radixWorkGroupSize;
			final int numBlocksTris = (numTris + radixWorkGroupSize - 1) / radixWorkGroupSize;

			// Calculate min/max of coordinates of the vertex buffer
			// This is used when generating morton codes. We only have 10 bits per axis so we want to maximize the resolution by using space for only what exists in the scene
			GL43C.glUseProgram(glMinMaxProgram);
			GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, tmpOutBuffer.glBufferId);
			GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 1, glMinMaxBuffer);
			GL43C.glUniform1ui(uniMinMaxNumItems, numVertices);
			GL43C.glDispatchCompute(numBlocksVertices, 1, 1);
			GL43C.glMemoryBarrier(GL43C.GL_SHADER_STORAGE_BARRIER_BIT);

			final int singleControlBufferSizeUnaligned = (4 * 1 + 4 * numBlocksTris * radixNumBuckets); // 1 uint(4 bytes) for group id counter, numBlocks*numBuckets uints for the statuses (4 bytes each)
			// Offsets for glBindBufferRange must be algined to the nearest GL_SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT
			final int offsetAlignment = GL43C.glGetInteger(GL43C.GL_SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT);
			assert isPowerOfTwo(offsetAlignment) : "glGetInteger(GL_SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT) returned a non-power-of-two (" + offsetAlignment + "), and this code expects a power of two";

			final int alignedControlBufferSize = ((singleControlBufferSizeUnaligned + offsetAlignment - 1) / offsetAlignment) * offsetAlignment; // NOTE: Assumes offsetAlignment is a power of two

			// We allocate numPasses of these control buffers at once, and instead of clearing the data every pass we just move the pointer over to the extra previously cleared data
			final int controlBufferRequiredSize = alignedControlBufferSize * radixNumPasses;

			updateBuffer(mortonKeyValueBuffer,
					GL43C.GL_ARRAY_BUFFER,
					numTris * 2 * 4,
					GL43C.GL_DYNAMIC_DRAW,
					CL12.CL_MEM_READ_WRITE);
			// Temp morton buffer is for double buffering during the sort
			updateBuffer(tmpMortonKeyValueBuffer,
					GL43C.GL_ARRAY_BUFFER,
					numTris * 2 * 4,
					GL43C.GL_DYNAMIC_DRAW,
					CL12.CL_MEM_READ_WRITE);

			// TODO: fill out the key value buffer with a compute shader
			// TODO: get min/max while doing that also (atomic min/max into local, atomic min/max to global)
			{ // TODO: REMOVE THIS
				final int[] keyValues = new int[numTris * 2];
				Random random = new Random();
				random.setSeed(48);
				for (int i = 0; i < numTris * 2; i += 2) {
					int r;
					do {
						r = random.nextInt();
					} while (r < 0);

					keyValues[i + 0] = i / 2;
					keyValues[i + 1] = r;
				}

				// Temporarily just put random values until we do the morton thing
				GL43C.glBindBuffer(GL43C.GL_SHADER_STORAGE_BUFFER, mortonKeyValueBuffer.glBufferId);
				GL43C.glBufferData(GL43C.GL_SHADER_STORAGE_BUFFER, keyValues, GL43C.GL_DYNAMIC_DRAW);
			}

			updateBuffer(radixControlBuffer,
					GL43C.GL_ARRAY_BUFFER,
					controlBufferRequiredSize,
					GL43C.GL_DYNAMIC_DRAW,
					CL12.CL_MEM_READ_WRITE);

			updateBuffer(radixDigitStartIndicesBuffer,
					GL43C.GL_ARRAY_BUFFER,
					4 * radixNumPasses * radixNumBuckets,
					GL43C.GL_DYNAMIC_DRAW,
					CL12.CL_MEM_READ_WRITE);

			// Clear the control buffers to zero
			GL43C.glBindBuffer(GL43C.GL_SHADER_STORAGE_BUFFER, radixControlBuffer.glBufferId);
			GL43C.glClearBufferData(GL43C.GL_SHADER_STORAGE_BUFFER, GL43C.GL_R32UI, GL43C.GL_RED, GL43C.GL_UNSIGNED_INT, (int[]) null);

			// Clear start indices to zero
			GL43C.glBindBuffer(GL43C.GL_SHADER_STORAGE_BUFFER, radixDigitStartIndicesBuffer.glBufferId);
			GL43C.glClearBufferData(GL43C.GL_SHADER_STORAGE_BUFFER, GL43C.GL_R32UI, GL43C.GL_RED, GL43C.GL_UNSIGNED_INT, (int[]) null);

			{
				final int N = numTris;
				GL43C.glQueryCounter(radixTimingQueries[0], GL43C.GL_TIMESTAMP);

				{ // Count the digits in the dataset, one set of counts per pass
					GL43C.glUseProgram(glRadixCountDigitsProgram);
					GL43C.glUniform1ui(uniRadixDigitCountNumItems, N);
					GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, mortonKeyValueBuffer.glBufferId);
					GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 1, radixDigitStartIndicesBuffer.glBufferId);

					GL43C.glDispatchCompute(numBlocksTris, 1, 1);
					GL43C.glMemoryBarrier(GL43C.GL_SHADER_STORAGE_BARRIER_BIT);

					GL43C.glEndQuery(GL43C.GL_TIME_ELAPSED);
				}

				{ // Compute start indices for each digit, for each pass, by calculating the prefix sum of digit counts
					GL43C.glQueryCounter(radixTimingQueries[1], GL43C.GL_TIMESTAMP);

					GL43C.glUseProgram(glRadixComputeStartIndices);
					GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, radixDigitStartIndicesBuffer.glBufferId);
					GL43C.glDispatchCompute(1, radixNumPasses, 1);
					GL43C.glMemoryBarrier(GL43C.GL_SHADER_STORAGE_BARRIER_BIT);

					GL43C.glEndQuery(GL43C.GL_TIME_ELAPSED);
				}

				GL43C.glQueryCounter(radixTimingQueries[2], GL43C.GL_TIMESTAMP);

				GL43C.glUseProgram(glRadixSortProgram);
				GL43C.glUniform1ui(uniRadixNumItems, N);

				GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, mortonKeyValueBuffer.glBufferId);
				GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 3, radixDigitStartIndicesBuffer.glBufferId);

				for (int pass_number = 0; pass_number < radixNumPasses; pass_number++) { // TODO: Inconsistent naming
					GLBuffer sourceBuffer = (pass_number & 1) == 0 ? mortonKeyValueBuffer : tmpMortonKeyValueBuffer;
					GLBuffer destinationBuffer = (pass_number & 1) == 0 ? tmpMortonKeyValueBuffer : mortonKeyValueBuffer;

					GL43C.glUniform1ui(uniRadixPassNumber, pass_number);
					GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, sourceBuffer.glBufferId);
					GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 1, destinationBuffer.glBufferId);
					// Shift over the control buffer to the one corresponding to this pass
					GL43C.glBindBufferRange(GL43C.GL_SHADER_STORAGE_BUFFER, 2, radixControlBuffer.glBufferId, alignedControlBufferSize * pass_number, singleControlBufferSizeUnaligned);
					GL43C.glDispatchCompute(numBlocksTris, 1, 1);
					GL43C.glMemoryBarrier(GL43C.GL_SHADER_STORAGE_BARRIER_BIT);
				}
				assert (radixNumPasses & 1) == 0 : "numPasses is " + radixNumPasses + " which is not even, and the above code expects it to be even (mortonKeyValueBuffer would hold the second to last step in the sort otherwise)";

				GL43C.glQueryCounter(radixTimingQueries[3], GL43C.GL_TIMESTAMP);
			}
			boolean profile = false;
			boolean checkSorted = true;
			if (profile) {
				long[] result = new long[1];
				GL43C.glGetQueryObjectui64v(radixTimingQueries[0], GL43C.GL_QUERY_RESULT, result);
				long oneNs = result[0];

				GL43C.glGetQueryObjectui64v(radixTimingQueries[1], GL43C.GL_QUERY_RESULT, result);
				long twoNs = result[0];

				GL43C.glGetQueryObjectui64v(radixTimingQueries[2], GL43C.GL_QUERY_RESULT, result);
				long threeNs = result[0];

				GL43C.glGetQueryObjectui64v(radixTimingQueries[3], GL43C.GL_QUERY_RESULT, result);
				long fourNs = result[0];

				double oneTwoMs = (twoNs - oneNs) / 1e6;
				double twoThreeMs = (threeNs - twoNs) / 1e6;
				double threeFourMs = (fourNs - threeNs) / 1e6;

				double oneFourMs = (fourNs - oneNs) / 1e6;

				System.out.println("Sorted " + numTris + " in " + oneFourMs + "ms");
				System.out.println("\tCount: " + oneTwoMs + "ms");
				System.out.println("\tPrefix: " + twoThreeMs + "ms");
				System.out.println("\tRadix: " + threeFourMs + "ms");
				double seconds = oneFourMs * 0.001;
				double itemsPerSecond = numTris / seconds;
				double gigaItemsPerSecond = itemsPerSecond * 1e-9;
				double gigaBytesPerSecond = gigaItemsPerSecond * 4;
				System.out.println(gigaItemsPerSecond + " giga items per second (" + gigaBytesPerSecond + " gigabytes per second)");
			}

			if (checkSorted) {
				int[] resultKeyValues = new int[numTris * 2];
				GL43C.glBindBuffer(GL43C.GL_SHADER_STORAGE_BUFFER, mortonKeyValueBuffer.glBufferId);
				GL43C.glGetBufferSubData(GL43C.GL_SHADER_STORAGE_BUFFER, 0, resultKeyValues);

				boolean sorted = true;
				try {
					int[] keyCounts = new int[numTris];
					for (int i = 0; i < numTris - 1; i++) {
						int key = resultKeyValues[i * 2 + 0];
						int value = resultKeyValues[i * 2 + 1];
						int nextValue = resultKeyValues[(i + 1) * 2 + 1];
						keyCounts[key]++;
						if (keyCounts[key] > 1) {
							System.out.println("\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!REPEATED KEYS!!!!! (" + key + ")\n");
							sorted = false;
							break;
						}
						if (value > nextValue) {
							System.out.println("\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!UNSORTED!!!\n");
							sorted = false;
							break;
						}
					}
				} catch (Exception e) {
					e.printStackTrace();
					sorted = false;
				}


				if (!sorted) {
					System.out.println("keys:");
					for (int i = 0; i < numTris; i++) {
						int key = resultKeyValues[i * 2 + 0];
						System.out.println(key);
					}

				/*System.out.println("DATA:");
				for (int i = 0; i < N; i++) {
					System.out.println(values[resultKeyValues[i]]);
				}*/
					shutDown();
				}
			}
		}
	}

	@Override
	public void drawScenePaint(int orientation, int pitchSin, int pitchCos, int yawSin, int yawCos, int x, int y, int z,
		SceneTilePaint paint, int tileZ, int tileX, int tileY,
		int zoom, int centerX, int centerY)
	{
		if (computeMode == ComputeMode.NONE)
		{
			targetBufferOffset += sceneUploader.upload(client.getScene(), paint,
				tileZ, tileX, tileY,
				vertexBuffer, uvBuffer,
				tileX << Perspective.LOCAL_COORD_BITS,
				tileY << Perspective.LOCAL_COORD_BITS,
				true
			);
		}
		else if (paint.getBufferLen() > 0)
		{
			final int localX = tileX << Perspective.LOCAL_COORD_BITS;
			final int localY = 0;
			final int localZ = tileY << Perspective.LOCAL_COORD_BITS;

			GpuIntBuffer b = modelBufferUnordered;
			++unorderedModels;

			b.ensureCapacity(8);
			IntBuffer buffer = b.getBuffer();
			buffer.put(paint.getBufferOffset());
			buffer.put(paint.getUvBufferOffset());
			buffer.put(2);
			buffer.put(targetBufferOffset);
			buffer.put(FLAG_SCENE_BUFFER);
			buffer.put(localX).put(localY).put(localZ);

			targetBufferOffset += 2 * 3;
		}
	}

	@Override
	public void drawSceneModel(int orientation, int pitchSin, int pitchCos, int yawSin, int yawCos, int x, int y, int z,
		SceneTileModel model, int tileZ, int tileX, int tileY,
		int zoom, int centerX, int centerY)
	{
		if (computeMode == ComputeMode.NONE)
		{
			targetBufferOffset += sceneUploader.upload(model,
				tileX, tileY,
				tileX << Perspective.LOCAL_COORD_BITS, tileY << Perspective.LOCAL_COORD_BITS,
				vertexBuffer, uvBuffer,
				true);
		}
		else if (model.getBufferLen() > 0)
		{
			final int localX = tileX << Perspective.LOCAL_COORD_BITS;
			final int localY = 0;
			final int localZ = tileY << Perspective.LOCAL_COORD_BITS;

			GpuIntBuffer b = modelBufferUnordered;
			++unorderedModels;

			b.ensureCapacity(8);
			IntBuffer buffer = b.getBuffer();
			buffer.put(model.getBufferOffset());
			buffer.put(model.getUvBufferOffset());
			buffer.put(model.getBufferLen() / 3);
			buffer.put(targetBufferOffset);
			buffer.put(FLAG_SCENE_BUFFER);
			buffer.put(localX).put(localY).put(localZ);

			targetBufferOffset += model.getBufferLen();
		}
	}

	private void prepareInterfaceTexture(int canvasWidth, int canvasHeight)
	{
		if (canvasWidth != lastCanvasWidth || canvasHeight != lastCanvasHeight)
		{
			lastCanvasWidth = canvasWidth;
			lastCanvasHeight = canvasHeight;

			GL43C.glBindBuffer(GL43C.GL_PIXEL_UNPACK_BUFFER, interfacePbo);
			GL43C.glBufferData(GL43C.GL_PIXEL_UNPACK_BUFFER, canvasWidth * canvasHeight * 4L, GL43C.GL_STREAM_DRAW);
			GL43C.glBindBuffer(GL43C.GL_PIXEL_UNPACK_BUFFER, 0);

			GL43C.glBindTexture(GL43C.GL_TEXTURE_2D, interfaceTexture);
			GL43C.glTexImage2D(GL43C.GL_TEXTURE_2D, 0, GL43C.GL_RGBA, canvasWidth, canvasHeight, 0, GL43C.GL_BGRA, GL43C.GL_UNSIGNED_BYTE, 0);
			GL43C.glBindTexture(GL43C.GL_TEXTURE_2D, 0);
		}

		final BufferProvider bufferProvider = client.getBufferProvider();
		final int[] pixels = bufferProvider.getPixels();
		final int width = bufferProvider.getWidth();
		final int height = bufferProvider.getHeight();

		GL43C.glBindBuffer(GL43C.GL_PIXEL_UNPACK_BUFFER, interfacePbo);
		GL43C.glMapBuffer(GL43C.GL_PIXEL_UNPACK_BUFFER, GL43C.GL_WRITE_ONLY)
			.asIntBuffer()
			.put(pixels, 0, width * height);
		GL43C.glUnmapBuffer(GL43C.GL_PIXEL_UNPACK_BUFFER);
		GL43C.glBindTexture(GL43C.GL_TEXTURE_2D, interfaceTexture);
		GL43C.glTexSubImage2D(GL43C.GL_TEXTURE_2D, 0, 0, 0, width, height, GL43C.GL_BGRA, GL43C.GL_UNSIGNED_INT_8_8_8_8_REV, 0);
		GL43C.glBindBuffer(GL43C.GL_PIXEL_UNPACK_BUFFER, 0);
		GL43C.glBindTexture(GL43C.GL_TEXTURE_2D, 0);
	}

	@Override
	public void draw(int overlayColor)
	{
		final GameState gameState = client.getGameState();
		if (gameState == GameState.STARTING)
		{
			return;
		}

		final int canvasHeight = client.getCanvasHeight();
		final int canvasWidth = client.getCanvasWidth();

		final int viewportHeight = client.getViewportHeight();
		final int viewportWidth = client.getViewportWidth();

		prepareInterfaceTexture(canvasWidth, canvasHeight);

		// Setup anti-aliasing
		final AntiAliasingMode antiAliasingMode = config.antiAliasingMode();
		final boolean aaEnabled = antiAliasingMode != AntiAliasingMode.DISABLED;

		if (aaEnabled)
		{
			GL43C.glEnable(GL43C.GL_MULTISAMPLE);

			final Dimension stretchedDimensions = client.getStretchedDimensions();

			final int stretchedCanvasWidth = client.isStretchedEnabled() ? stretchedDimensions.width : canvasWidth;
			final int stretchedCanvasHeight = client.isStretchedEnabled() ? stretchedDimensions.height : canvasHeight;

			// Re-create fbo
			if (lastStretchedCanvasWidth != stretchedCanvasWidth
				|| lastStretchedCanvasHeight != stretchedCanvasHeight
				|| lastAntiAliasingMode != antiAliasingMode)
			{
				shutdownAAFbo();

				// Bind default FBO to check whether anti-aliasing is forced
				GL43C.glBindFramebuffer(GL43C.GL_FRAMEBUFFER, awtContext.getFramebuffer(false));
				final int forcedAASamples = GL43C.glGetInteger(GL43C.GL_SAMPLES);
				final int maxSamples = GL43C.glGetInteger(GL43C.GL_MAX_SAMPLES);
				final int samples = forcedAASamples != 0 ? forcedAASamples :
					Math.min(antiAliasingMode.getSamples(), maxSamples);

				log.debug("AA samples: {}, max samples: {}, forced samples: {}", samples, maxSamples, forcedAASamples);

				initAAFbo(stretchedCanvasWidth, stretchedCanvasHeight, samples);

				lastStretchedCanvasWidth = stretchedCanvasWidth;
				lastStretchedCanvasHeight = stretchedCanvasHeight;
			}

			GL43C.glBindFramebuffer(GL43C.GL_DRAW_FRAMEBUFFER, fboSceneHandle);
		}
		else
		{
			GL43C.glDisable(GL43C.GL_MULTISAMPLE);
			shutdownAAFbo();
		}

		lastAntiAliasingMode = antiAliasingMode;

		// Clear scene
		int sky = client.getSkyboxColor();
		GL43C.glClearColor((sky >> 16 & 0xFF) / 255f, (sky >> 8 & 0xFF) / 255f, (sky & 0xFF) / 255f, 1f);
		GL43C.glClear(GL43C.GL_COLOR_BUFFER_BIT);

		// Draw 3d scene
		if (gameState.getState() >= GameState.LOADING.getState())
		{
			final TextureProvider textureProvider = client.getTextureProvider();
			if (textureArrayId == -1)
			{
				// lazy init textures as they may not be loaded at plugin start.
				// this will return -1 and retry if not all textures are loaded yet, too.
				textureArrayId = textureManager.initTextureArray(textureProvider);
				if (textureArrayId > -1)
				{
					// if texture upload is successful, compute and set texture animations
					float[] texAnims = textureManager.computeTextureAnimations(textureProvider);
					GL43C.glUseProgram(glProgram);
					GL43C.glUniform2fv(uniTextureAnimations, texAnims);
					GL43C.glUseProgram(0);
				}
			}

			int renderWidthOff = viewportOffsetX;
			int renderHeightOff = viewportOffsetY;
			int renderCanvasHeight = canvasHeight;
			int renderViewportHeight = viewportHeight;
			int renderViewportWidth = viewportWidth;

			// Setup anisotropic filtering
			final int anisotropicFilteringLevel = config.anisotropicFilteringLevel();

			if (textureArrayId != -1 && lastAnisotropicFilteringLevel != anisotropicFilteringLevel)
			{
				textureManager.setAnisotropicFilteringLevel(textureArrayId, anisotropicFilteringLevel);
				lastAnisotropicFilteringLevel = anisotropicFilteringLevel;
			}

			if (client.isStretchedEnabled())
			{
				Dimension dim = client.getStretchedDimensions();
				renderCanvasHeight = dim.height;

				double scaleFactorY = dim.getHeight() / canvasHeight;
				double scaleFactorX = dim.getWidth() / canvasWidth;

				// Pad the viewport a little because having ints for our viewport dimensions can introduce off-by-one errors.
				final int padding = 1;

				// Ceil the sizes because even if the size is 599.1 we want to treat it as size 600 (i.e. render to the x=599 pixel).
				renderViewportHeight = (int) Math.ceil(scaleFactorY * (renderViewportHeight)) + padding * 2;
				renderViewportWidth = (int) Math.ceil(scaleFactorX * (renderViewportWidth)) + padding * 2;

				// Floor the offsets because even if the offset is 4.9, we want to render to the x=4 pixel anyway.
				renderHeightOff = (int) Math.floor(scaleFactorY * (renderHeightOff)) - padding;
				renderWidthOff = (int) Math.floor(scaleFactorX * (renderWidthOff)) - padding;
			}

			glDpiAwareViewport(renderWidthOff, renderCanvasHeight - renderViewportHeight - renderHeightOff, renderViewportWidth, renderViewportHeight);

			GL43C.glUseProgram(glProgram);

			final int drawDistance = getDrawDistance();
			final int fogDepth = config.fogDepth();
			GL43C.glUniform1i(uniUseFog, fogDepth > 0 ? 1 : 0);
			GL43C.glUniform4f(uniFogColor, (sky >> 16 & 0xFF) / 255f, (sky >> 8 & 0xFF) / 255f, (sky & 0xFF) / 255f, 1f);
			GL43C.glUniform1i(uniFogDepth, fogDepth);
			GL43C.glUniform1i(uniDrawDistance, drawDistance * Perspective.LOCAL_TILE_SIZE);
			GL43C.glUniform1i(uniExpandedMapLoadingChunks, client.getExpandedMapLoading());

			// Brightness happens to also be stored in the texture provider, so we use that
			GL43C.glUniform1f(uniBrightness, (float) textureProvider.getBrightness());
			GL43C.glUniform1f(uniSmoothBanding, config.smoothBanding() ? 0f : 1f);
			GL43C.glUniform1i(uniColorBlindMode, config.colorBlindMode().ordinal());
			GL43C.glUniform1f(uniTextureLightMode, config.brightTextures() ? 1f : 0f);
			if (gameState == GameState.LOGGED_IN)
			{
				// avoid textures animating during loading
				GL43C.glUniform1i(uniTick, client.getGameCycle());
			}

			float[] modelMatrix = Mat4.identity();

			float[] viewMatrix = Mat4.rotateX((float) -(Math.PI - cameraPitch));
			Mat4.mul(viewMatrix, Mat4.rotateY((float) cameraYaw));
			Mat4.mul(viewMatrix, Mat4.translate((float) -cameraX, (float) -cameraY, (float) -cameraZ));

			float[] projectionMatrix = Mat4.scale(client.getScale(), client.getScale(), 1);
			Mat4.mul(projectionMatrix, Mat4.projection(viewportWidth, viewportHeight, 50));

			float[] mvp = projectionMatrix.clone();
			Mat4.mul(mvp, viewMatrix);
			Mat4.mul(mvp, modelMatrix);
			GL43C.glUniformMatrix4fv(uniProjectionMatrix, false, mvp);

			// Bind uniforms
			GL43C.glUniformBlockBinding(glProgram, uniBlockMain, 0);
			GL43C.glUniform1i(uniTextures, 1); // texture sampler array is bound to texture1

			// We just allow the GL to do face culling. Note this requires the priority renderer
			// to have logic to disregard culled faces in the priority depth testing.
			GL43C.glEnable(GL43C.GL_CULL_FACE);

			// Enable blending for alpha
			GL43C.glEnable(GL43C.GL_BLEND);
			GL43C.glBlendFuncSeparate(GL43C.GL_SRC_ALPHA, GL43C.GL_ONE_MINUS_SRC_ALPHA, GL43C.GL_ONE, GL43C.GL_ONE);

			// Draw buffers
			if (computeMode != ComputeMode.NONE)
			{
				if (computeMode == ComputeMode.OPENGL)
				{
					// Before reading the SSBOs written to from postDrawScene() we must insert a barrier
					GL43C.glMemoryBarrier(GL43C.GL_SHADER_STORAGE_BARRIER_BIT);
				}
				else
				{
					// Wait for the command queue to finish, so that we know the compute is done
					openCLManager.finish();
				}

				// Draw using the output buffer of the compute
				GL43C.glBindVertexArray(vaoCompute);
			}
			else
			{
				// Only use the temporary buffers, which will contain the full scene
				GL43C.glBindVertexArray(vaoTemp);
			}

			GL43C.glDrawArrays(GL43C.GL_TRIANGLES, 0, targetBufferOffset);

			GL43C.glDisable(GL43C.GL_BLEND);
			GL43C.glDisable(GL43C.GL_CULL_FACE);

			GL43C.glUseProgram(0);
		}

		if (aaEnabled)
		{
			int width = lastStretchedCanvasWidth;
			int height = lastStretchedCanvasHeight;

			if (OSType.getOSType() != OSType.MacOS)
			{
				final GraphicsConfiguration graphicsConfiguration = clientUI.getGraphicsConfiguration();
				final AffineTransform transform = graphicsConfiguration.getDefaultTransform();

				width = getScaledValue(transform.getScaleX(), width);
				height = getScaledValue(transform.getScaleY(), height);
			}

			GL43C.glBindFramebuffer(GL43C.GL_READ_FRAMEBUFFER, fboSceneHandle);
			GL43C.glBindFramebuffer(GL43C.GL_DRAW_FRAMEBUFFER, awtContext.getFramebuffer(false));
			GL43C.glBlitFramebuffer(0, 0, width, height, 0, 0, width, height,
				GL43C.GL_COLOR_BUFFER_BIT, GL43C.GL_NEAREST);

			// Reset
			GL43C.glBindFramebuffer(GL43C.GL_READ_FRAMEBUFFER, awtContext.getFramebuffer(false));
		}

		int vertexCount = targetBufferOffset; // NOTE: 4 from is vA,vB,vC,alphaPrioritycolor

		// Texture on UI
		drawUi(overlayColor, canvasHeight, canvasWidth, vertexCount);

		vertexBuffer.clear();
		uvBuffer.clear();
		modelBuffer.clear();
		modelBufferSmall.clear();
		modelBufferUnordered.clear();

		smallModels = largeModels = unorderedModels = 0;
		tempOffset = 0;
		tempUvOffset = 0;

		try
		{
			awtContext.swapBuffers();
		}
		catch (RuntimeException ex)
		{
			// this is always fatal
			if (!canvas.isValid())
			{
				// this might be AWT shutting down on VM shutdown, ignore it
				return;
			}

			throw ex;
		}

		drawManager.processDrawComplete(this::screenshot);

		GL43C.glBindFramebuffer(GL43C.GL_FRAMEBUFFER, awtContext.getFramebuffer(false));

		checkGLErrors();
	}

	private void drawUi(final int overlayColor, final int canvasHeight, final int canvasWidth, final int vertexCount)
	{
		GL43C.glEnable(GL43C.GL_BLEND);
		GL43C.glBlendFunc(GL43C.GL_ONE, GL43C.GL_ONE_MINUS_SRC_ALPHA);
		GL43C.glBindTexture(GL43C.GL_TEXTURE_2D, interfaceTexture);

		// Use the texture bound in the first pass
		final UIScalingMode uiScalingMode = config.uiScalingMode();
		GL43C.glUseProgram(glUiProgram);
		GL43C.glUniform1i(uniTex, 0);
		GL43C.glUniform1i(uniTexSamplingMode, uiScalingMode.getMode());
		GL43C.glUniform2i(uniTexSourceDimensions, canvasWidth, canvasHeight);
		GL43C.glUniform1i(uniUiColorBlindMode, config.colorBlindMode().ordinal());
		GL43C.glUniform4f(uniUiAlphaOverlay,
			(overlayColor >> 16 & 0xFF) / 255f,
			(overlayColor >> 8 & 0xFF) / 255f,
			(overlayColor & 0xFF) / 255f,
			(overlayColor >>> 24) / 255f
		);

		if (client.isStretchedEnabled())
		{
			Dimension dim = client.getStretchedDimensions();
			glDpiAwareViewport(0, 0, dim.width, dim.height);
			GL43C.glUniform2i(uniTexTargetDimensions, dim.width, dim.height);
		}
		else
		{
			glDpiAwareViewport(0, 0, canvasWidth, canvasHeight);
			GL43C.glUniform2i(uniTexTargetDimensions, canvasWidth, canvasHeight);
		}

		// Set the sampling function used when stretching the UI.
		// This is probably better done with sampler objects instead of texture parameters, but this is easier and likely more portable.
		// See https://www.khronos.org/opengl/wiki/Sampler_Object for details.
		if (client.isStretchedEnabled())
		{
			// GL_NEAREST makes sampling for bicubic/xBR simpler, so it should be used whenever linear isn't
			final int function = uiScalingMode == UIScalingMode.LINEAR ? GL43C.GL_LINEAR : GL43C.GL_NEAREST;
			GL43C.glTexParameteri(GL43C.GL_TEXTURE_2D, GL43C.GL_TEXTURE_MIN_FILTER, function);
			GL43C.glTexParameteri(GL43C.GL_TEXTURE_2D, GL43C.GL_TEXTURE_MAG_FILTER, function);
		}



		float[] viewMatrix = Mat4.rotateX((float) -(Math.PI - cameraPitch));
		Mat4.mul(viewMatrix, Mat4.rotateY((float) cameraYaw));
		Mat4.mul(viewMatrix, Mat4.translate((float) -cameraX, (float) -cameraY, (float) -cameraZ));

		//float[] projectionMatrix = Mat4.scale(client.getScale(), client.getScale(), 1);
		//Mat4.mul(projectionMatrix, Mat4.projection(client.getViewportWidth(), client.getViewportHeight(), 50));

		float aspectX = (float) client.getViewportWidth() / client.getScale();
		float aspectY = (float) client.getViewportHeight() / client.getScale();

		GL43C.glUniform2f(uniUiAspectScaling, aspectX, aspectY);

		GL43C.glUniformMatrix4fv(uniUiViewMatrix, false, viewMatrix);
		//GL43C.glUniformMatrix4fv(uniUiProjection, false, projectionMatrix);

		TextureProvider textureProvider = client.getTextureProvider();
		GL43C.glUniform1f(uniUiBrightness, (float) textureProvider.getBrightness());
		GL43C.glUniform1i(uniUiVertexCount, vertexCount);
		GL43C.glUniform3f(uniUiCameraPosition, (float) cameraX, (float) cameraY, (float) cameraZ);

		GL43C.glBindBufferBase(GL43C.GL_SHADER_STORAGE_BUFFER, 0, tmpOutBuffer.glBufferId);

		// Texture on UI
		GL43C.glBindVertexArray(vaoUiHandle);
		GL43C.glDrawArrays(GL43C.GL_TRIANGLE_FAN, 0, 4);

		// Reset
		GL43C.glBindTexture(GL43C.GL_TEXTURE_2D, 0);
		GL43C.glBindVertexArray(0);
		GL43C.glUseProgram(0);
		GL43C.glBlendFunc(GL43C.GL_SRC_ALPHA, GL43C.GL_ONE_MINUS_SRC_ALPHA);
		GL43C.glDisable(GL43C.GL_BLEND);
	}

	/**
	 * Convert the front framebuffer to an Image
	 *
	 * @return
	 */
	private Image screenshot()
	{
		int width = client.getCanvasWidth();
		int height = client.getCanvasHeight();

		if (client.isStretchedEnabled())
		{
			Dimension dim = client.getStretchedDimensions();
			width = dim.width;
			height = dim.height;
		}

		if (OSType.getOSType() != OSType.MacOS)
		{
			final GraphicsConfiguration graphicsConfiguration = clientUI.getGraphicsConfiguration();
			final AffineTransform t = graphicsConfiguration.getDefaultTransform();
			width = getScaledValue(t.getScaleX(), width);
			height = getScaledValue(t.getScaleY(), height);
		}

		ByteBuffer buffer = ByteBuffer.allocateDirect(width * height * 4)
			.order(ByteOrder.nativeOrder());

		GL43C.glReadBuffer(awtContext.getBufferMode());
		GL43C.glReadPixels(0, 0, width, height, GL43C.GL_RGBA, GL43C.GL_UNSIGNED_BYTE, buffer);

		BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
		int[] pixels = ((DataBufferInt) image.getRaster().getDataBuffer()).getData();

		for (int y = 0; y < height; ++y)
		{
			for (int x = 0; x < width; ++x)
			{
				int r = buffer.get() & 0xff;
				int g = buffer.get() & 0xff;
				int b = buffer.get() & 0xff;
				buffer.get(); // alpha

				pixels[(height - y - 1) * width + x] = (r << 16) | (g << 8) | b;
			}
		}

		return image;
	}

	@Override
	public void animate(Texture texture, int diff)
	{
		// texture animation happens on gpu
	}

	@Subscribe
	public void onGameStateChanged(GameStateChanged gameStateChanged)
	{
		if (gameStateChanged.getGameState() == GameState.LOGIN_SCREEN)
		{
			// Avoid drawing the last frame's buffer during LOADING after LOGIN_SCREEN
			targetBufferOffset = 0;
		}
	}

	@Override
	public void loadScene(Scene scene)
	{
		if (computeMode == ComputeMode.NONE)
		{
			return;
		}

		GpuIntBuffer vertexBuffer = new GpuIntBuffer();
		GpuFloatBuffer uvBuffer = new GpuFloatBuffer();

		sceneUploader.upload(scene, vertexBuffer, uvBuffer);

		vertexBuffer.flip();
		uvBuffer.flip();

		nextSceneVertexBuffer = vertexBuffer;
		nextSceneTexBuffer = uvBuffer;
		nextSceneId = sceneUploader.sceneId;
	}

	private void uploadTileHeights(Scene scene)
	{
		if (tileHeightTex != 0)
		{
			GL43C.glDeleteTextures(tileHeightTex);
			tileHeightTex = 0;
		}

		final int TILEHEIGHT_BUFFER_SIZE = Constants.MAX_Z * Constants.EXTENDED_SCENE_SIZE * Constants.EXTENDED_SCENE_SIZE * Short.BYTES;
		ShortBuffer tileBuffer = ByteBuffer
			.allocateDirect(TILEHEIGHT_BUFFER_SIZE)
			.order(ByteOrder.nativeOrder())
			.asShortBuffer();

		int[][][] tileHeights = scene.getTileHeights();
		for (int z = 0; z < Constants.MAX_Z; ++z)
		{
			for (int y = 0; y < Constants.EXTENDED_SCENE_SIZE; ++y)
			{
				for (int x = 0; x < Constants.EXTENDED_SCENE_SIZE; ++x)
				{
					int h = tileHeights[z][x][y];
					assert (h & 0b111) == 0;
					h >>= 3;
					tileBuffer.put((short) h);
				}
			}
		}
		tileBuffer.flip();

		tileHeightTex = GL43C.glGenTextures();
		GL43C.glBindTexture(GL43C.GL_TEXTURE_3D, tileHeightTex);
		GL43C.glTexParameteri(GL43C.GL_TEXTURE_3D, GL43C.GL_TEXTURE_MIN_FILTER, GL43C.GL_NEAREST);
		GL43C.glTexParameteri(GL43C.GL_TEXTURE_3D, GL43C.GL_TEXTURE_MAG_FILTER, GL43C.GL_NEAREST);
		GL43C.glTexParameteri(GL43C.GL_TEXTURE_3D, GL43C.GL_TEXTURE_WRAP_S, GL43C.GL_CLAMP_TO_EDGE);
		GL43C.glTexParameteri(GL43C.GL_TEXTURE_3D, GL43C.GL_TEXTURE_WRAP_T, GL43C.GL_CLAMP_TO_EDGE);
		GL43C.glTexImage3D(GL43C.GL_TEXTURE_3D, 0, GL43C.GL_R16I,
			Constants.EXTENDED_SCENE_SIZE, Constants.EXTENDED_SCENE_SIZE, Constants.MAX_Z,
			0, GL43C.GL_RED_INTEGER, GL43C.GL_SHORT, tileBuffer);
		GL43C.glBindTexture(GL43C.GL_TEXTURE_3D, 0);

		// bind to texture 2
		GL43C.glActiveTexture(GL43C.GL_TEXTURE2);
		GL43C.glBindTexture(GL43C.GL_TEXTURE_3D, tileHeightTex); // binding = 2 in the shader
		GL43C.glActiveTexture(GL43C.GL_TEXTURE0);
	}

	@Override
	public void swapScene(Scene scene)
	{
		if (computeMode == ComputeMode.NONE)
		{
			return;
		}

		if (computeMode == ComputeMode.OPENCL)
		{
			openCLManager.uploadTileHeights(scene);
		}
		else
		{
			assert computeMode == ComputeMode.OPENGL;
			uploadTileHeights(scene);
		}

		sceneId = nextSceneId;
		updateBuffer(sceneVertexBuffer, GL43C.GL_ARRAY_BUFFER, nextSceneVertexBuffer.getBuffer(), GL43C.GL_STATIC_COPY, CL12.CL_MEM_READ_ONLY);
		updateBuffer(sceneUvBuffer, GL43C.GL_ARRAY_BUFFER, nextSceneTexBuffer.getBuffer(), GL43C.GL_STATIC_COPY, CL12.CL_MEM_READ_ONLY);

		nextSceneVertexBuffer = null;
		nextSceneTexBuffer = null;
		nextSceneId = -1;

		checkGLErrors();
	}

	@Override
	public boolean tileInFrustum(Scene scene, int pitchSin, int pitchCos, int yawSin, int yawCos, int cameraX, int cameraY, int cameraZ, int plane, int msx, int msy)
	{
		int[][][] tileHeights = scene.getTileHeights();
		int x = ((msx - SCENE_OFFSET) << Perspective.LOCAL_COORD_BITS) + 64 - cameraX;
		int z = ((msy - SCENE_OFFSET) << Perspective.LOCAL_COORD_BITS) + 64 - cameraZ;
		int y = Math.max(
			Math.max(tileHeights[plane][msx][msy], tileHeights[plane][msx][msy + 1]),
			Math.max(tileHeights[plane][msx + 1][msy], tileHeights[plane][msx + 1][msy + 1])
		) + GROUND_MIN_Y - cameraY;

		int radius = 96; // ~ 64 * sqrt(2)

		int zoom = client.get3dZoom();
		int Rasterizer3D_clipMidX2 = client.getRasterizer3D_clipMidX2();
		int Rasterizer3D_clipNegativeMidX = client.getRasterizer3D_clipNegativeMidX();
		int Rasterizer3D_clipNegativeMidY = client.getRasterizer3D_clipNegativeMidY();

		int var11 = yawCos * z - yawSin * x >> 16;
		int var12 = pitchSin * y + pitchCos * var11 >> 16;
		int var13 = pitchCos * radius >> 16;
		int depth = var12 + var13;
		if (depth > 50)
		{
			int rx = z * yawSin + yawCos * x >> 16;
			int var16 = (rx - radius) * zoom;
			int var17 = (rx + radius) * zoom;
			// left && right
			if (var16 < Rasterizer3D_clipMidX2 * depth && var17 > Rasterizer3D_clipNegativeMidX * depth)
			{
				int ry = pitchCos * y - var11 * pitchSin >> 16;
				int ybottom = pitchSin * radius >> 16;
				int var20 = (ry + ybottom) * zoom;
				// top
				if (var20 > Rasterizer3D_clipNegativeMidY * depth)
				{
					// we don't test the bottom so we don't have to find the height of all the models on the tile
					return true;
				}
			}
		}
		return false;
	}

	/**
	 * Check is a model is visible and should be drawn.
	 */
	private boolean isVisible(Model model, int pitchSin, int pitchCos, int yawSin, int yawCos, int x, int y, int z)
	{
		model.calculateBoundsCylinder();

		final int xzMag = model.getXYZMag();
		final int bottomY = model.getBottomY();
		final int zoom = client.get3dZoom();
		final int modelHeight = model.getModelHeight();

		int Rasterizer3D_clipMidX2 = client.getRasterizer3D_clipMidX2(); // width / 2
		int Rasterizer3D_clipNegativeMidX = client.getRasterizer3D_clipNegativeMidX(); // -width / 2
		int Rasterizer3D_clipNegativeMidY = client.getRasterizer3D_clipNegativeMidY(); // -height / 2
		int Rasterizer3D_clipMidY2 = client.getRasterizer3D_clipMidY2(); // height / 2

		int var11 = yawCos * z - yawSin * x >> 16;
		int var12 = pitchSin * y + pitchCos * var11 >> 16;
		int var13 = pitchCos * xzMag >> 16;
		int depth = var12 + var13;
		if (depth > 50)
		{
			int rx = z * yawSin + yawCos * x >> 16;
			int var16 = (rx - xzMag) * zoom;
			if (var16 / depth < Rasterizer3D_clipMidX2)
			{
				int var17 = (rx + xzMag) * zoom;
				if (var17 / depth > Rasterizer3D_clipNegativeMidX)
				{
					int ry = pitchCos * y - var11 * pitchSin >> 16;
					int yheight = pitchSin * xzMag >> 16;
					int ybottom = (pitchCos * bottomY >> 16) + yheight; // use bottom height instead of y pos for height
					int var20 = (ry + ybottom) * zoom;
					if (var20 / depth > Rasterizer3D_clipNegativeMidY)
					{
						int ytop = (pitchCos * modelHeight >> 16) + yheight;
						int var22 = (ry - ytop) * zoom;
						return var22 / depth < Rasterizer3D_clipMidY2;
					}
				}
			}
		}
		return false;
	}

	/**
	 * Draw a renderable in the scene
	 *
	 * @param renderable
	 * @param orientation
	 * @param pitchSin
	 * @param pitchCos
	 * @param yawSin
	 * @param yawCos
	 * @param x
	 * @param y
	 * @param z
	 * @param hash
	 */
	@Override
	public void draw(Renderable renderable, int orientation, int pitchSin, int pitchCos, int yawSin, int yawCos, int x, int y, int z, long hash)
	{
		Model model, offsetModel;
		if (renderable instanceof Model)
		{
			model = (Model) renderable;
			offsetModel = model.getUnskewedModel();
			if (offsetModel == null)
			{
				offsetModel = model;
			}
		}
		else
		{
			model = renderable.getModel();
			if (model == null)
			{
				return;
			}
			offsetModel = model;
		}

		if (computeMode == ComputeMode.NONE)
		{
			// Apply height to renderable from the model
			if (model != renderable)
			{
				renderable.setModelHeight(model.getModelHeight());
			}

			if (!isVisible(model, pitchSin, pitchCos, yawSin, yawCos, x, y, z))
			{
				return;
			}

			client.checkClickbox(model, orientation, pitchSin, pitchCos, yawSin, yawCos, x, y, z, hash);

			targetBufferOffset += sceneUploader.pushSortedModel(
				model, orientation,
				pitchSin, pitchCos,
				yawSin, yawCos,
				x, y, z,
				vertexBuffer, uvBuffer);
		}
		// Model may be in the scene buffer
		else if (offsetModel.getSceneId() == sceneId)
		{
			assert model == renderable;

			if (!isVisible(model, pitchSin, pitchCos, yawSin, yawCos, x, y, z))
			{
				return;
			}

			client.checkClickbox(model, orientation, pitchSin, pitchCos, yawSin, yawCos, x, y, z, hash);

			int tc = Math.min(MAX_TRIANGLE, offsetModel.getFaceCount());
			int uvOffset = offsetModel.getUvBufferOffset();
			int plane = (int) ((hash >> 49) & 3);
			boolean hillskew = offsetModel != model;

			GpuIntBuffer b = bufferForTriangles(tc);

			b.ensureCapacity(8);
			IntBuffer buffer = b.getBuffer();
			buffer.put(offsetModel.getBufferOffset());
			buffer.put(uvOffset);
			buffer.put(tc);
			buffer.put(targetBufferOffset);
			buffer.put(FLAG_SCENE_BUFFER | (hillskew ? (1 << 26) : 0) | (plane << 24) | (model.getRadius() << 12) | orientation);
			buffer.put(x + client.getCameraX2()).put(y + client.getCameraY2()).put(z + client.getCameraZ2());

			targetBufferOffset += tc * 3;
		}
		else
		{
			// Temporary model (animated or otherwise not a static Model on the scene)

			// Apply height to renderable from the model
			if (model != renderable)
			{
				renderable.setModelHeight(model.getModelHeight());
			}

			if (!isVisible(model, pitchSin, pitchCos, yawSin, yawCos, x, y, z))
			{
				return;
			}

			client.checkClickbox(model, orientation, pitchSin, pitchCos, yawSin, yawCos, x, y, z, hash);

			boolean hasUv = model.getFaceTextures() != null;

			int len = sceneUploader.pushModel(model, vertexBuffer, uvBuffer);

			GpuIntBuffer b = bufferForTriangles(len / 3);

			b.ensureCapacity(8);
			IntBuffer buffer = b.getBuffer();
			buffer.put(tempOffset);
			buffer.put(hasUv ? tempUvOffset : -1);
			buffer.put(len / 3);
			buffer.put(targetBufferOffset);
			buffer.put((model.getRadius() << 12) | orientation);
			buffer.put(x + client.getCameraX2()).put(y + client.getCameraY2()).put(z + client.getCameraZ2());

			tempOffset += len;
			if (hasUv)
			{
				tempUvOffset += len;
			}

			targetBufferOffset += len;
		}
	}

	/**
	 * returns the correct buffer based on triangle count and updates model count
	 *
	 * @param triangles
	 * @return
	 */
	private GpuIntBuffer bufferForTriangles(int triangles)
	{
		if (triangles <= SMALL_TRIANGLE_COUNT)
		{
			++smallModels;
			return modelBufferSmall;
		}
		else
		{
			++largeModels;
			return modelBuffer;
		}
	}

	private int getScaledValue(final double scale, final int value)
	{
		return (int) (value * scale + .5);
	}

	private void glDpiAwareViewport(final int x, final int y, final int width, final int height)
	{
		if (OSType.getOSType() == OSType.MacOS)
		{
			// macos handles DPI scaling for us already
			GL43C.glViewport(x, y, width, height);
		}
		else
		{
			final GraphicsConfiguration graphicsConfiguration = clientUI.getGraphicsConfiguration();
			final AffineTransform t = graphicsConfiguration.getDefaultTransform();
			GL43C.glViewport(
				getScaledValue(t.getScaleX(), x),
				getScaledValue(t.getScaleY(), y),
				getScaledValue(t.getScaleX(), width),
				getScaledValue(t.getScaleY(), height));
		}
	}

	private int getDrawDistance()
	{
		final int limit = computeMode != ComputeMode.NONE ? MAX_DISTANCE : DEFAULT_DISTANCE;
		return Ints.constrainToRange(config.drawDistance(), 0, limit);
	}

	private void updateBuffer(@Nonnull GLBuffer glBuffer, int target, @Nonnull IntBuffer data, int usage, long clFlags)
	{
		int size = data.remaining() << 2;
		updateBuffer(glBuffer, target, size, usage, clFlags);
		GL43C.glBufferSubData(target, 0, data);
	}

	private void updateBuffer(@Nonnull GLBuffer glBuffer, int target, @Nonnull FloatBuffer data, int usage, long clFlags)
	{
		int size = data.remaining() << 2;
		updateBuffer(glBuffer, target, size, usage, clFlags);
		GL43C.glBufferSubData(target, 0, data);
	}

	private void updateBuffer(@Nonnull GLBuffer glBuffer, int target, int size, int usage, long clFlags)
	{
		GL43C.glBindBuffer(target, glBuffer.glBufferId);
		if (glCapabilities.glInvalidateBufferData != 0L)
		{
			// https://www.khronos.org/opengl/wiki/Buffer_Object_Streaming suggests buffer re-specification is useful
			// to avoid implicit synching. We always need to trash the whole buffer anyway so this can't hurt.
			GL43C.glInvalidateBufferData(glBuffer.glBufferId);
		}
		if (size > glBuffer.size)
		{
			int newSize = Math.max(1024, nextPowerOfTwo(size));
			log.trace("Buffer resize: {} {} -> {}", glBuffer.name, glBuffer.size, newSize);

			glBuffer.size = newSize;
			GL43C.glBufferData(target, newSize, usage);
			recreateCLBuffer(glBuffer, clFlags);
		}
	}

	private static int nextPowerOfTwo(int v)
	{
		v--;
		v |= v >> 1;
		v |= v >> 2;
		v |= v >> 4;
		v |= v >> 8;
		v |= v >> 16;
		v++;
		return v;
	}

	private static boolean isPowerOfTwo(int n) {
		if (n <= 0) return false;
		return (n & -n) == n;
	}

	private void recreateCLBuffer(GLBuffer glBuffer, long clFlags)
	{
		if (computeMode == ComputeMode.OPENCL)
		{
			if (glBuffer.clBuffer != -1)
			{
				CL10.clReleaseMemObject(glBuffer.clBuffer);
			}
			if (glBuffer.size == 0)
			{
				glBuffer.clBuffer = -1;
			}
			else
			{
				glBuffer.clBuffer = CL10GL.clCreateFromGLBuffer(openCLManager.context, clFlags, glBuffer.glBufferId, (int[]) null);
			}
		}
	}

	private void checkGLErrors()
	{
		if (!log.isDebugEnabled())
		{
			return;
		}

		for (; ; )
		{
			int err = GL43C.glGetError();
			if (err == GL43C.GL_NO_ERROR)
			{
				return;
			}

			String errStr;
			switch (err)
			{
				case GL43C.GL_INVALID_ENUM:
					errStr = "INVALID_ENUM";
					break;
				case GL43C.GL_INVALID_VALUE:
					errStr = "INVALID_VALUE";
					break;
				case GL43C.GL_INVALID_OPERATION:
					errStr = "INVALID_OPERATION";
					break;
				case GL43C.GL_INVALID_FRAMEBUFFER_OPERATION:
					errStr = "INVALID_FRAMEBUFFER_OPERATION";
					break;
				default:
					errStr = "" + err;
					break;
			}

			log.debug("glGetError:", new Exception(errStr));
		}
	}
}
