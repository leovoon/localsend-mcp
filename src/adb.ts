import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export interface AdbDevice {
  id: string;
  type: 'usb' | 'wifi';
  status: string;
}

/**
 * Lists connected ADB devices (USB and Wireless).
 */
export async function listAdbDevices(): Promise<AdbDevice[]> {
  try {
    const { stdout } = await execFileAsync('adb', ['devices'], { timeout: 3000 });
    const lines = stdout.split('\n').map(l => l.trim()).filter(Boolean);
    const devices: AdbDevice[] = [];

    for (let i = 1; i < lines.length; i++) {
      const parts = lines[i].split(/\s+/);
      if (parts.length >= 2) {
        const id = parts[0];
        const status = parts[1];
        const type = id.includes(':') ? 'wifi' : 'usb';
        devices.push({ id, type, status });
      }
    }
    return devices;
  } catch {
    return [];
  }
}

/**
 * Wakes an Android device screen and launches LocalSend into the foreground.
 */
export async function wakeAndLaunchLocalSend(deviceId?: string): Promise<{ success: boolean; message: string }> {
  try {
    const argsPrefix = deviceId ? ['-s', deviceId] : [];
    // 1. Wake screen if dim/off
    await execFileAsync('adb', [...argsPrefix, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'], { timeout: 3000 }).catch(() => {});
    // 2. Launch LocalSend MainActivity
    await execFileAsync('adb', [...argsPrefix, 'shell', 'am', 'start', '-n', 'org.localsend.localsend_app/.MainActivity', '-W'], { timeout: 5000 });
    return { success: true, message: `Successfully woken and brought LocalSend to foreground${deviceId ? ` on ${deviceId}` : ''}.` };
  } catch (err: any) {
    return { success: false, message: `Failed to wake device: ${err?.message || String(err)}` };
  }
}

/**
 * Retrieves the Wi-Fi IP address of a connected Android device via ADB.
 */
export async function getAdbDeviceIp(deviceId?: string): Promise<string | null> {
  try {
    const argsPrefix = deviceId ? ['-s', deviceId] : [];
    const { stdout } = await execFileAsync('adb', [...argsPrefix, 'shell', 'ip', 'route'], { timeout: 3000 });
    // Match line like "192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.50"
    const match = stdout.match(/dev\s+wlan0\s+.*src\s+(\d+\.\d+\.\d+\.\d+)/);
    if (match && match[1]) {
      return match[1];
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Opens a URL in the default browser on an Android device via ADB.
 */
export async function openUrlOnAndroid(url: string, deviceId?: string): Promise<{ success: boolean; message: string }> {
  try {
    const argsPrefix = deviceId ? ['-s', deviceId] : [];
    await execFileAsync('adb', [...argsPrefix, 'shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', url], { timeout: 4000 });
    return { success: true, message: `Opened URL on Android: ${url}` };
  } catch (err: any) {
    return { success: false, message: `Failed to open URL: ${err?.message || String(err)}` };
  }
}
