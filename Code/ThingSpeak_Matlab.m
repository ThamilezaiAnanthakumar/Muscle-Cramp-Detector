% --- Step 1: Real-Time Data Reception via ThingSpeak ---
readChannelID = 2776369; % Replace with your ThingSpeak channel ID
readAPIKey = 'XFJ0EYVNX1WDPYQD'; % Replace with your ThingSpeak read API key
fieldID_signal = 1; % Field ID for EMG signal
fieldID_temp = 2;   % Field ID for temperature signal
fieldID_sto2 = 3;   % Field ID for SaO2
data_length = 125;  % Total samples to fetch (125 samples at ~1 Hz default rate)

% Fetch data from ThingSpeak
[data, timeStamps] = thingSpeakRead(readChannelID, 'Fields', fieldID_signal, 'NumPoints', data_length, 'ReadKey', readAPIKey);
[temperature_data, ~] = thingSpeakRead(readChannelID, 'Fields', fieldID_temp, 'NumPoints', data_length, 'ReadKey', readAPIKey);
[sto2_data, ~] = thingSpeakRead(readChannelID, 'Fields', fieldID_sto2, 'NumPoints', data_length, 'ReadKey', readAPIKey);
%disp(data);
%disp(temperature_data);
%disp(sto2_data);
% Remove invalid or non-numeric data
data = data(~isnan(data));
temperature_data = temperature_data(~isnan(temperature_data));
sto2_data = sto2_data(~isnan(sto2_data));

% Check for empty arrays
if isempty(data) || isempty(temperature_data) || isempty(sto2_data)
    error('No valid numeric data received from ThingSpeak. Check your channel data.');
end

% Convert timeStamps to seconds relative to start time
t_start = timeStamps(1); % Reference start time
time_in_seconds = seconds(timeStamps - t_start); % Numeric time vector
time_in_seconds = time_in_seconds(1:length(data)); % Match time length to data

fs = 1; % Sampling frequency in Hz (default ThingSpeak rate ~1 Hz)
calibration_signal = sin(2 * pi * 0.1 * time_in_seconds); % Example calibration signal
calibration_temp = 4 * cos(2 * pi * 0.1 * time_in_seconds);

real_time_signal = data;  % Real-time EMG signal
real_time_temp = temperature_data; % Real-time temperature

% --- Step 2: Calibration Analysis ---
% RMS and threshold for calibration
rms_values_calibration = sqrt(movmean(calibration_signal.^2, 5));
threshold_calibration = mean(rms_values_calibration) + 2 * std(rms_values_calibration);
burst_indices_calibration = find(rms_values_calibration > threshold_calibration);

% Baseline for temperature
baseline_mean = mean(calibration_temp);
baseline_std = std(calibration_temp);
temp_threshold = baseline_mean + 2 * baseline_std;

% --- Step 3: Real-Time EMG Signal Analysis ---
% RMS for real-time signal
rms_values_real_time = sqrt(movmean(real_time_signal.^2, 5));
spike_indices = find(rms_values_real_time > threshold_calibration);

% Normalize metrics
if ~isempty(spike_indices) && ~isempty(burst_indices_calibration)
    RMS_max = max(rms_values_calibration) + 0.1;
    RMS_min = min(rms_values_calibration) - 0.1;
    normalized_rms = (rms_values_real_time(spike_indices) - RMS_min) / (RMS_max - RMS_min);
    normalized_rms = min(max(normalized_rms, 0), 1);

    % Burst duration
    burst_duration_real_time = diff([0; spike_indices(:)]) / fs;
    Duration_max = max(diff([0; burst_indices_calibration])) / fs;
    Duration_min = min(diff([0; burst_indices_calibration])) / fs;
    
    % Ensure compatible sizes for normalization
    if ~isempty(burst_duration_real_time)
        normalized_duration = (burst_duration_real_time - Duration_min) / (Duration_max - Duration_min);
        normalized_duration = min(max(normalized_duration, 0), 1);
    else
        normalized_duration = 0;
    end

    % Cramp score
    max_len = min([length(normalized_rms), length(normalized_duration)]);
    cramp_score = 0.5 * normalized_rms(1:max_len) + 0.5 * normalized_duration(1:max_len);
    rms_values_cramp_score = sqrt(movmean(cramp_score.^2, 5));
else
    cramp_score = 0;
    rms_values_cramp_score = 0;
end

% --- Step 4: Real-Time Temperature Analysis ---
spike_indices_temp = find(real_time_temp > temp_threshold);
oscillations = abs(diff(real_time_temp)) > 0.5; % Rapid changes

% Normalization for temperature
temp_normalized = (real_time_temp - baseline_mean) / (baseline_std * 2);
temp_normalized = min(max(temp_normalized, 0), 1);

% --- Step 5: Cramp Detection Decision ---
SaO2_value = mean(sto2_data); % Use the average SaO2 value
if SaO2_value < 40
    result_to_send = 'Cramp Detected';
elseif 40 <= SaO2_value && SaO2_value < 75
    if ~isempty(spike_indices_temp) || any(oscillations)
        result_to_send = 'Cramp Detected';
    else
        percentage = 0.6 * (SaO2_value / 100) + 0.4 * rms_values_cramp_score;
        result_to_send = sprintf('Cramp percentage: %.2f%%', percentage * 100);
    end
else
    result_to_send = sprintf('Cramp percentage: %.2f%%', rms_values_cramp_score * 100);
end

writeAPIKey = '0O430J900EZDY24U'; % Replace with your Write API Key
channelID =  2776369;        % Replace with your Channel ID
dataValue = result_to_send;                      % Replace with your data
result_to_send = str2num(result_to_send)
% Write to Field 4
thingSpeakWrite(channelID, 'Fields', 4, 'Values', dataValue, 'WriteKey', writeAPIKey);
disp('Data written to Field 4');

% Display results
disp('Cramp Detection Result:');
disp(result_to_send);