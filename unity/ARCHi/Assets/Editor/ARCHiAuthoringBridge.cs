using MCPForUnity.Editor.Services.Transport.Transports;
using UnityEditor;
using UnityEngine;

// Isolated authoring project only. No ARCHi runtime or companion state lives here.
public static class ARCHiAuthoringBridge
{
    [MenuItem("ARCHi/Authoring/Start Local MCP")]
    public static void Start()
    {
        EditorPrefs.SetBool("MCPForUnity.TelemetryDisabled", true);
        StdioBridgeHost.Start();
        Debug.Log("ARCHI_AUTHORING_BRIDGE_READY port=" + StdioBridgeHost.GetCurrentPort());
    }

    [MenuItem("ARCHi/Authoring/Stop Local MCP")]
    public static void Stop() => StdioBridgeHost.Stop();
}
