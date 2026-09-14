using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

// Isolated presentation fixture. It does not participate in ARCHi's app build.
public static class ARCHiPearlReadability
{
    const string AssetPath = "Assets/ARCHiStudies/PearlStudyV1/archi-pearl-study-v1.png";
    const string ScenePath = "Assets/Scenes/ARCHiPearlReadabilityV1.unity";
    const string MenuRoot = "ARCHi/Authoring/";
    const int FixtureLayer = 30;
    const int Width = 1200;
    const int Height = 900;

    [Serializable] class Contract { public string sha256; }
    [Serializable] class Sample { public string name; public float requestedPixels; public float measuredPixels; public string asset; }
    [Serializable] class Receipt
    {
        public string status, unityVersion, scene, sourceSha256, importedSha256, pngAsset, render;
        public int importedWidth, importedHeight, transparentPixels, partialAlphaPixels, opaquePixels;
        public bool importedSourceHasAlpha, alphaIsTransparency, sceneDirty;
        public string filterMode, compression;
        public int renderWidth = Width, renderHeight = Height;
        public Sample[] samples;
    }

    static string ProjectRoot => Directory.GetParent(Application.dataPath).FullName;
    static string OutputRoot => Path.GetFullPath(Path.Combine(ProjectRoot, "../../starter-study-v1/unity-validation"));
    static string Hash(string path)
    {
        using (var algorithm = SHA256.Create())
            return BitConverter.ToString(algorithm.ComputeHash(File.ReadAllBytes(path))).Replace("-", "").ToLowerInvariant();
    }

    static void CheckProject()
    {
        if (!ProjectRoot.EndsWith("/output/creative-tools/unity/ARCHiPresentation", StringComparison.Ordinal))
            throw new InvalidOperationException("Wrong Unity project.");
        if (EditorApplication.isPlayingOrWillChangePlaymode)
            throw new InvalidOperationException("Leave Play Mode before presentation authoring.");
    }

    [MenuItem(MenuRoot + "Create Pearl Readability Scene")]
    public static void Create()
    {
        CheckProject();
        for (int i = 0; i < SceneManager.sceneCount; i++)
            if (SceneManager.GetSceneAt(i).isDirty) throw new InvalidOperationException("Preserve unsaved scene changes before creating the fixture.");
        if (File.Exists(ScenePath)) throw new InvalidOperationException("Presentation scene already exists; use Inspect and Render Pearl Scene.");
        var contract = JsonUtility.FromJson<Contract>(File.ReadAllText("Assets/ARCHiStudies/PearlStudyV1/asset-contract.json"));
        if (Hash(AssetPath) != contract.sha256) throw new InvalidOperationException("Imported PNG differs from the reviewed Blender export.");
        AssetDatabase.ImportAsset(AssetPath, ImportAssetOptions.ForceSynchronousImport);
        var importer = (TextureImporter)AssetImporter.GetAtPath(AssetPath);
        importer.textureType = TextureImporterType.Sprite;
        importer.spriteImportMode = SpriteImportMode.Single;
        importer.spritePixelsPerUnit = 100;
        importer.alphaSource = TextureImporterAlphaSource.FromInput;
        importer.alphaIsTransparency = true;
        importer.mipmapEnabled = false;
        importer.sRGBTexture = true;
        importer.isReadable = true;
        importer.filterMode = FilterMode.Bilinear;
        importer.wrapMode = TextureWrapMode.Clamp;
        importer.textureCompression = TextureImporterCompression.Uncompressed;
        var settings = new TextureImporterSettings();
        importer.ReadTextureSettings(settings);
        settings.spriteMeshType = SpriteMeshType.FullRect;
        settings.spritePivot = new Vector2(0.5f, 0.5f);
        settings.spriteAlignment = (int)SpriteAlignment.Center;
        importer.SetTextureSettings(settings);
        importer.SaveAndReimport();
        var sprite = AssetDatabase.LoadAssetAtPath<Sprite>(AssetPath);
        if (sprite == null) throw new InvalidOperationException("Imported sprite unavailable.");
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Additive);
        SceneManager.SetActiveScene(scene);
        var camera = new GameObject("Pearl_Readability_Camera").AddComponent<Camera>();
        camera.gameObject.layer = FixtureLayer;
        camera.transform.position = new Vector3(0, 0, -10);
        camera.orthographic = true;
        camera.orthographicSize = Height / 200f;
        camera.aspect = (float)Width / Height;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = Color.black;
        camera.cullingMask = 1 << FixtureLayer;
        camera.allowHDR = false;
        camera.allowMSAA = false;
        for (int row = 0; row < 2; row++)
        {
            bool light = row == 0;
            float centerY = light ? 2.25f : -2.25f;
            Color background = light ? new Color(0.965f, 0.953f, 0.984f) : new Color(0.075f, 0.080f, 0.118f);
            var panel = GameObject.CreatePrimitive(PrimitiveType.Quad);
            panel.name = light ? "Light_Background" : "Dark_Background";
            panel.layer = FixtureLayer;
            UnityEngine.Object.DestroyImmediate(panel.GetComponent<Collider>());
            panel.transform.position = new Vector3(0, centerY, 1);
            panel.transform.localScale = new Vector3(12, 4.5f, 1);
            var material = new Material(Shader.Find("Unlit/Color")) { color = background };
            string materialPath = "Assets/ARCHiStudies/PearlStudyV1/" + panel.name + ".mat";
            AssetDatabase.CreateAsset(material, materialPath);
            panel.GetComponent<Renderer>().sharedMaterial = material;
            int[] sizes = {90, 180, 310};
            for (int column = 0; column < sizes.Length; column++)
            {
                float x = (column - 1) * 4;
                var art = new GameObject((light ? "Light_" : "Dark_") + sizes[column] + "px_Pearl");
                art.layer = FixtureLayer;
                art.transform.position = new Vector3(x, centerY - 0.20f, 0);
                art.transform.localScale = Vector3.one * sizes[column] / 512f;
                art.AddComponent<SpriteRenderer>().sprite = sprite;
                var label = new GameObject((light ? "Light_" : "Dark_") + sizes[column] + "px_Label");
                label.layer = FixtureLayer;
                label.transform.position = new Vector3(x, centerY + 1.75f, -0.5f);
                var text = label.AddComponent<TextMesh>();
                text.text = sizes[column] + " px · " + (light ? "Light" : "Dark");
                text.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
                text.fontSize = 48;
                text.characterSize = 0.045f;
                text.anchor = TextAnchor.MiddleCenter;
                text.color = light ? new Color(0.22f, 0.18f, 0.30f) : new Color(0.85f, 0.83f, 0.94f);
                label.GetComponent<MeshRenderer>().sharedMaterial = text.font.material;
            }
        }
        if (!EditorSceneManager.SaveScene(scene, ScenePath)) throw new IOException("Could not save presentation scene.");
        AssetDatabase.SaveAssets();
        InspectAndRender();
    }

    [MenuItem(MenuRoot + "Inspect and Render Pearl Scene")]
    public static void InspectAndRender()
    {
        CheckProject();
        var scene = SceneManager.GetActiveScene();
        if (scene.path != ScenePath || scene.isDirty) throw new InvalidOperationException("Open the saved Pearl presentation scene without unsaved changes.");
        var camera = scene.GetRootGameObjects().SelectMany(x => x.GetComponentsInChildren<Camera>()).Single();
        var texture = AssetDatabase.LoadAssetAtPath<Texture2D>(AssetPath);
        var importer = (TextureImporter)AssetImporter.GetAtPath(AssetPath);
        var contract = JsonUtility.FromJson<Contract>(File.ReadAllText("Assets/ARCHiStudies/PearlStudyV1/asset-contract.json"));
        var receipt = new Receipt {
            status = "UNITY_SAVED_SCENE_RENDERED_NATIVE_INTEGRATION_UNVERIFIED", unityVersion = Application.unityVersion,
            scene = ScenePath, sourceSha256 = contract.sha256, importedSha256 = Hash(AssetPath), pngAsset = AssetPath,
            importedWidth = texture.width, importedHeight = texture.height, importedSourceHasAlpha = importer.DoesSourceTextureHaveAlpha(),
            alphaIsTransparency = importer.alphaIsTransparency, filterMode = importer.filterMode.ToString(),
            compression = importer.textureCompression.ToString(), sceneDirty = scene.isDirty
        };
        foreach (var pixel in texture.GetPixels32()) {
            if (pixel.a == 0) receipt.transparentPixels++;
            else if (pixel.a == 255) receipt.opaquePixels++;
            else receipt.partialAlphaPixels++;
        }
        receipt.samples = scene.GetRootGameObjects().SelectMany(x => x.GetComponentsInChildren<SpriteRenderer>()).Select(renderer => new Sample {
            name = renderer.name, requestedPixels = float.Parse(renderer.name.Split('_')[1].Replace("px", "")),
            measuredPixels = renderer.bounds.size.x * Height / (2 * camera.orthographicSize),
            asset = AssetDatabase.GetAssetPath(renderer.sprite)
        }).ToArray();
        if (receipt.importedSha256 != receipt.sourceSha256 || receipt.importedWidth != 512 || receipt.importedHeight != 512 || receipt.transparentPixels == 0 || receipt.samples.Length != 6)
            throw new InvalidOperationException("PNG identity or presentation fixture contract failed.");
        Directory.CreateDirectory(OutputRoot);
        var oldTarget = camera.targetTexture;
        var oldActive = RenderTexture.active;
        var target = new RenderTexture(Width, Height, 24, RenderTextureFormat.ARGB32);
        var pixels = new Texture2D(Width, Height, TextureFormat.RGB24, false);
        try {
            camera.targetTexture = target;
            camera.Render();
            RenderTexture.active = target;
            pixels.ReadPixels(new Rect(0, 0, Width, Height), 0, 0);
            pixels.Apply();
            receipt.render = Path.Combine(OutputRoot, "pearl-readability-unity.png");
            File.WriteAllBytes(receipt.render, pixels.EncodeToPNG());
        } finally {
            camera.targetTexture = oldTarget;
            RenderTexture.active = oldActive;
            UnityEngine.Object.DestroyImmediate(target);
            UnityEngine.Object.DestroyImmediate(pixels);
        }
        File.WriteAllText(Path.Combine(OutputRoot, "unity-readback.json"), JsonUtility.ToJson(receipt, true));
        Debug.Log("ARCHi Pearl presentation rendered: " + receipt.render);
    }
}
