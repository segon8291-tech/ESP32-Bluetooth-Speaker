@echo off
cls
echo ===================================================
echo   ESP32 Bluetooth Speaker Project Setup
echo ===================================================
echo.

:: Check for curl
where curl >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] 'curl' was not found on your system.
    echo Please update Windows or install curl.
    pause
    exit /b
)

:: --- STEP 1: Arduino IDE ---
echo [STEP 1] Arduino IDE Installation
:ask_ide
set "choice_ide="
set /p "choice_ide=Download and run Arduino IDE installer? (Y/N): "
if /i "%choice_ide%"=="N" (
    echo Skipping Arduino IDE.
    goto step2
)
if /i "%choice_ide%" neq "Y" (
    echo Invalid input. Please enter Y or N.
    goto ask_ide
)

echo.
echo Downloading Arduino IDE v2.3.10...
curl -L -o "arduino-ide_installer.exe" "https://downloads.arduino.cc/arduino-ide/arduino-ide_2.3.10_Windows_64bit.exe"

if not exist "arduino-ide_installer.exe" (
    echo [ERROR] Failed to download the file. Check your internet connection.
    pause
    goto step2
)
echo Download complete!
echo.
echo Starting the installer...
echo Waiting for the installer to be closed...
start /wait "" "arduino-ide_installer.exe"
echo Installer closed.
echo.

:: --- STEP 2: Project Creation ---
:step2
echo [STEP 2] ESP32 Project and Instructions Creation
:ask_proj
set "choice_proj="
set /p "choice_proj=Create project and instructions in this folder? (Y/N): "
if /i "%choice_proj%"=="N" (
    echo Skipping project creation.
    goto end
)
if /i "%choice_proj%" neq "Y" (
    echo Invalid input. Please enter Y or N.
    goto ask_proj
)

echo.
echo Creating project folder...
set "PROJ_DIR=ESP32_Bluetooth_Speaker"
set "PROJ_FILE=%PROJ_DIR%\ESP32_Bluetooth_Speaker.ino"

if not exist "%PROJ_DIR%" (
    mkdir "%PROJ_DIR%"
)

:: Create temporary VBScript using safe ASCII-only echo commands
echo Set fso = CreateObject("Scripting.FileSystemObject") > temp.vbs
echo Set inFile = fso.OpenTextFile(WScript.Arguments(0), 1) >> temp.vbs
echo Set outFile = fso.CreateTextFile(WScript.Arguments(1), True) >> temp.vbs
echo startMarker = WScript.Arguments(2) >> temp.vbs
echo endMarker = WScript.Arguments(3) >> temp.vbs
echo writeState = False >> temp.vbs
echo Do Until inFile.AtEndOfStream >> temp.vbs
echo     line = inFile.ReadLine >> temp.vbs
echo     If Trim(line) = startMarker Then >> temp.vbs
echo         writeState = True >> temp.vbs
echo     ElseIf Trim(line) = endMarker Then >> temp.vbs
echo         writeState = False >> temp.vbs
echo     ElseIf writeState Then >> temp.vbs
echo         outFile.WriteLine line >> temp.vbs
echo     End If >> temp.vbs
echo Loop >> temp.vbs
echo inFile.Close >> temp.vbs
echo outFile.Close >> temp.vbs

:: Extract C++ code
cscript //nologo temp.vbs "%~f0" "%PROJ_FILE%" "::===BEGIN_CPP_CODE===" "::===END_CPP_CODE==="

:: Extract Instructions
cscript //nologo temp.vbs "%~f0" "README_INSTRUCTION.txt" "::===BEGIN_INSTRUCTION===" "::===END_INSTRUCTION==="

del temp.vbs

if exist "%PROJ_FILE%" (
    echo Project successfully created at: %PROJ_FILE%
)
if exist "README_INSTRUCTION.txt" (
    echo Instruction successfully created: README_INSTRUCTION.txt
    echo Opening instruction in Notepad...
    start notepad.exe "README_INSTRUCTION.txt"
)
echo.

:end
if exist "arduino-ide_installer.exe" (
    del "arduino-ide_installer.exe" >nul 2>&1
)
echo Done.
pause
exit /b

::======================================================================
:: NO NOT EDIT MARKERS BEYOND THIS POINT.
::======================================================================
::===BEGIN_CPP_CODE===
#include "BluetoothA2DPSink.h"
#include "driver/i2s.h"
#include "driver/dac.h"

BluetoothA2DPSink a2dp_sink;

#define LED_PIN 22
#define NEXT_BUTTON_PIN 4
#define PLAY_PAUSE_BUTTON_PIN 14  
#define PREV_BUTTON_PIN 13

enum ToneType {
    TONE_CONNECT,      
    TONE_DISCONNECT   
};

volatile ToneType pendingTone;
volatile bool playPendingTone = false;
volatile bool is_tone_playing = false; 

volatile bool is_playing_state = false;
volatile uint32_t last_button_press_time = 0; 

void initI2S() {
    i2s_config_t i2s_config = {
        .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX | I2S_MODE_DAC_BUILT_IN),
        .sample_rate = 44100, 
        .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
        .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
        .communication_format = I2S_COMM_FORMAT_STAND_I2S,
        .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
        .dma_buf_count = 8,
        .dma_buf_len = 64, 
        .use_apll = false,
        .tx_desc_auto_clear = true
    };
    
    i2s_driver_install(I2S_NUM_0, &i2s_config, 0, NULL);
    i2s_set_dac_mode(I2S_DAC_CHANNEL_RIGHT_EN); 
    i2s_set_pin(I2S_NUM_0, NULL);
    
    i2s_stop(I2S_NUM_0);
    dac_output_disable(DAC_CHANNEL_1);
}

void checkButtons() {
    static uint32_t last_debounce_time = 0;
    if (millis() - last_debounce_time < 250) return; 
    
    static bool prev_next_state = HIGH;
    static bool prev_play_state = HIGH;
    static bool prev_back_state = HIGH;

    bool next_state = digitalRead(NEXT_BUTTON_PIN);
    bool play_state = digitalRead(PLAY_PAUSE_BUTTON_PIN);
    bool back_state = digitalRead(PREV_BUTTON_PIN);

    if (next_state == LOW && prev_next_state == HIGH) {
        Serial.println("[BTN] Next Track triggered");
        a2dp_sink.next();
        last_debounce_time = millis();
    }
    
    if (play_state == LOW && prev_play_state == HIGH) {
        Serial.println("[BTN] Play/Pause triggered");
        last_debounce_time = millis();
        last_button_press_time = millis(); 

        is_playing_state = !is_playing_state;

        if (!is_playing_state) {
            Serial.println("[BTN] Action: PAUSE");
            a2dp_sink.pause();
        } else {
            Serial.println("[BTN] Action: PLAY");
            a2dp_sink.play();
        }
    }
    
    if (back_state == LOW && prev_back_state == HIGH) {
        Serial.println("[BTN] Previous Track triggered");
        a2dp_sink.previous();
        last_debounce_time = millis();
    }

    prev_next_state = next_state;
    prev_play_state = play_state;
    prev_back_state = back_state;
}

void on_connection_state_changed(esp_a2d_connection_state_t state, void *obj) {
    switch (state) {
        case ESP_A2D_CONNECTION_STATE_CONNECTED: {
            Serial.println("[BT] Device Connected!");
            pendingTone = TONE_CONNECT;
            playPendingTone = true;
            break;
        }
        case ESP_A2D_CONNECTION_STATE_DISCONNECTED: {
            Serial.println("[BT] Device Disconnected!");
            pendingTone = TONE_DISCONNECT;
            playPendingTone = true;
            break;
        }
        default:
            break;
    }
}

void on_audio_state_changed(esp_a2d_audio_state_t state, void *obj) {
    bool new_playing_state = false;
    switch (state) {
        case ESP_A2D_AUDIO_STATE_STARTED: {
            Serial.println("[BT] Audio stream started.");
            new_playing_state = true;
            if (!is_tone_playing) {
                dac_output_enable(DAC_CHANNEL_1);
                i2s_start(I2S_NUM_0);
            }
            break;
        }
        case ESP_A2D_AUDIO_STATE_STOPPED: { 
            Serial.println("[BT] Audio stream paused/stopped.");
            new_playing_state = false;
            if (!is_tone_playing) {
                i2s_stop(I2S_NUM_0);
                dac_output_disable(DAC_CHANNEL_1);
            }
            ledcWrite(LED_PIN, 0);
            break;
        }
        default:
            return;
    }

    if (millis() - last_button_press_time > 1500) {
        is_playing_state = new_playing_state;
    }
}

void read_data_stream(const uint8_t *data, uint32_t length) {
    if (is_tone_playing) {
        return; 
    }

    int raw_volume = a2dp_sink.get_volume();
    float volume_scale = (float)raw_volume / 127.0f;

    uint8_t mutable_data[length];
    
    const int16_t *incoming_samples = (const int16_t *)data;
    int16_t *output_samples = (int16_t *)mutable_data;
    uint32_t sample_count = length / 2;

    int32_t max_peak = 0; 

    for (uint32_t i = 0; i < sample_count; i++) {
        int16_t sample = incoming_samples[i];

        float scaled = (float)sample * volume_scale;

        int32_t abs_sample = abs((int32_t)scaled);
        if (abs_sample > max_peak) {
            max_peak = abs_sample;
        }

        int32_t temp = (int32_t)scaled + 32768;
        
        if (temp > 65535) temp = 65535;
        if (temp < 0) temp = 0;
        
        output_samples[i] = (int16_t)((uint16_t)temp);
    }

    int led_duty = (max_peak * 255) / 32768;
    if (led_duty > 255) led_duty = 255;
    if (led_duty < 0) led_duty = 0;

    ledcWrite(LED_PIN, led_duty);

    size_t bytes_written;
    i2s_write(I2S_NUM_0, mutable_data, length, &bytes_written, portMAX_DELAY);
}

void playTone(ToneType type) {
    is_tone_playing = true; 
    ledcWrite(LED_PIN, 0);  
    
    dac_output_enable(DAC_CHANNEL_1);
    i2s_start(I2S_NUM_0);
    
    int sample_rate = 44100; 
    uint8_t block[512];
    size_t bytes_written;
    
    if (type == TONE_CONNECT) {
        float freqs[3] = { 523.25, 659.25, 783.99 };
        float phase = 0.0;
        for (int note = 0; note < 3; note++) {
            float freq = freqs[note];
            int num_samples = 0.12 * sample_rate; 
            for (int s = 0; s < num_samples; s += 128) {
                int chunk = (128 < num_samples - s) ? 128 : (num_samples - s);
                for (int i = 0; i < chunk; i++) {
                    float val = sin(phase);
                    phase += 2.0 * PI * freq / sample_rate;
                    if (phase >= 2.0 * PI) phase -= 2.0 * PI;
                    
                    float env = 1.0;
                    int current_sample = s + i;
                    if (current_sample < 0.015 * sample_rate) {
                        env = (float)current_sample / (0.015 * sample_rate);
                    } else if (current_sample > num_samples - 0.02 * sample_rate) {
                        env = (float)(num_samples - current_sample) / (0.02 * sample_rate);
                    }
                    
                    uint8_t dac_val = (uint8_t)(val * 127.0 * env + 128.0);
                    int idx = i * 4;
                    block[idx] = 0x00;
                    block[idx+1] = dac_val;
                    block[idx+2] = 0x00;
                    block[idx+3] = dac_val;
                }
                i2s_write(I2S_NUM_0, block, chunk * 4, &bytes_written, portMAX_DELAY);
            }
        }
    }
    else if (type == TONE_DISCONNECT) {
        float start_freq = 440.0;
        float end_freq = 220.0;
        int num_samples = 0.4 * sample_rate; 
        float phase = 0.0;
        for (int s = 0; s < num_samples; s += 128) {
            int chunk = (128 < num_samples - s) ? 128 : (num_samples - s);
            float progress = (float)s / num_samples;
            float freq = start_freq + (end_freq - start_freq) * progress;
            
            for (int i = 0; i < chunk; i++) {
                float val = sin(phase);
                phase += 2.0 * PI * freq / sample_rate;
                if (phase >= 2.0 * PI) phase -= 2.0 * PI;
                
                float env = 1.0 - ((float)(s + i) / num_samples);
                if (env < 0) env = 0;
                
                uint8_t dac_val = (uint8_t)(val * 127.0 * env + 128.0);
                int idx = i * 4;
                block[idx] = 0x00;
                block[idx+1] = dac_val;
                block[idx+2] = 0x00;
                block[idx+3] = dac_val;
            }
            i2s_write(I2S_NUM_0, block, chunk * 4, &bytes_written, portMAX_DELAY);
        }
    }
    
    uint16_t silence_frame[2] = { 0x8000, 0x8000 };
    for (int i = 0; i < 256; i++) {
        i2s_write(I2S_NUM_0, silence_frame, sizeof(silence_frame), &bytes_written, portMAX_DELAY);
    }
    vTaskDelay(50 / portTICK_PERIOD_MS);
    
    i2s_stop(I2S_NUM_0);
    dac_output_disable(DAC_CHANNEL_1);
    
    is_tone_playing = false; 
}

void setup() {
    Serial.begin(115200);

    pinMode(NEXT_BUTTON_PIN, INPUT_PULLUP);
    pinMode(PLAY_PAUSE_BUTTON_PIN, INPUT_PULLUP);
    pinMode(PREV_BUTTON_PIN, INPUT_PULLUP);

    initI2S();
    
    ledcAttach(LED_PIN, 5000, 8); 
    ledcWrite(LED_PIN, 0);        
    
    a2dp_sink.set_on_connection_state_changed(on_connection_state_changed);
    a2dp_sink.set_on_audio_state_changed(on_audio_state_changed);
    
    a2dp_sink.set_stream_reader(read_data_stream, false);
    
    a2dp_sink.start("Bluetooth Speaker");
}

void loop() {
    if (playPendingTone) {
        playPendingTone = false;
        playTone(pendingTone);
    }

    checkButtons();

    delay(1); 
}
::===END_CPP_CODE===

::===BEGIN_INSTRUCTION===
===================================================================
INSTRUCTION FOR INSTALLING LIBRARIES AND SETTING UP THE ESP32 PROJECT
===================================================================

You have successfully created the project! To make the code compile and run,
you need to configure the environment in the Arduino IDE by following these steps:

STEP 1: Add ESP32 Board Support to Arduino IDE
-------------------------------------------------------------------
1. Launch the installed Arduino IDE.
2. Go to the top menu: File -> Preferences.
3. Find the "Additional boards manager URLs" text field.
4. Copy and paste the following URL into that field:
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   (If there are already other URLs in this field, separate them with a comma
   or insert this link on a new line).
5. Click "OK" to save the preferences.

STEP 2: Install ESP32 Platform in the Boards Manager
-------------------------------------------------------------------
1. Go to: Tools -> Board -> Boards Manager...
2. In the search box in the top-left corner, type: esp32
3. Find the board package by "Espressif Systems" in the search results.
4. Click the "Install" button and wait for the installation process to complete.

STEP 3: Install the BluetoothA2DPSink Library
-------------------------------------------------------------------
This step is required for the "#include "BluetoothA2DPSink.h"" header to work.
1. Go to: Sketch -> Include Library -> Manage Libraries...
2. In the Library Manager search box, type: ESP32-A2DP
3. Find the library authored by "Phil Schatzmann".
4. Click the "Install" button.
5. If the IDE prompts you to install other dependent libraries (like "Arduino-DSP" or similar),
   make sure to choose "Install all".

STEP 4: Configure Partition Scheme (CRITICAL!)
-------------------------------------------------------------------
The Bluetooth A2DP code requires a large amount of the microcontroller's Flash memory.
By default, the 1.2 MB sketch limit will be exceeded, and compilation will fail with a "Sketch too big" error.
1. Connect your ESP32 board to your PC via a USB cable.
2. Select your board model: Tools -> Board -> ESP32 Arduino -> (e.g., ESP32 Dev Module).
3. Select the correct port: Tools -> Port -> (choose the COM port of your board).
4. Go to: Tools -> Partition Scheme, and change the default option to one of the following:
   - "Huge APP (3MB No OTA/1MB SPIFFS)"
   - or "No OTA (2MB APP/2MB SPIFFS)"

STEP 5: Upload the Firmware to the Microcontroller
-------------------------------------------------------------------
1. Open the "ESP32_Bluetooth_Speaker.ino" project file from the created folder.
2. Click the round "Upload" button (the arrow icon in the top-left corner of the Arduino IDE).
3. Wait for the compilation and upload to finish. You should see "Done uploading" at the bottom.
4. After rebooting, your ESP32 will start broadcasting Bluetooth audio under the name "Bluetooth Speaker".

===================================================================
Pin Specifications Used in the Code:
- LED_PIN = 22 (connected to the peak level indicator LED)
- NEXT_BUTTON_PIN = 4 (Next track button)
- PLAY_PAUSE_BUTTON_PIN = 14 (Play / Pause button)
- PREV_BUTTON_PIN = 13 (Previous track button)
- Analog audio output (right channel) is taken from GPIO25 (built-in DAC1)
===================================================================
::===END_INSTRUCTION===