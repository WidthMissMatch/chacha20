function matlab_uart_test(port_name, baud_rate)
% MATLAB_UART_TEST  Send ChaCha20-Poly1305 test vector over UART, verify response.
%
%   matlab_uart_test('/dev/ttyUSB0', 115200)
%   matlab_uart_test('COM3')                   % Windows, default 115200
%
%   Protocol (TX → FPGA):
%     [0xAA] [32B key] [12B nonce] [64B plaintext] [1B XOR checksum] = 110 bytes
%
%   Protocol (RX ← FPGA):
%     [64B ciphertext] [16B Poly1305 tag] = 80 bytes
%
%   Uses RFC 8439 Section 2.4.2 test vector by default.

    if nargin < 1, port_name = '/dev/ttyUSB0'; end
    if nargin < 2, baud_rate = 115200; end

    %% RFC 8439 Test Vector
    % Key: 00:01:02:...:1F
    key = uint8(0:31);

    % Nonce: 00 00 00 00  00 00 00 4A  00 00 00 00
    nonce = uint8([0 0 0 0  0 0 0 hex2dec('4A')  0 0 0 0]);

    % Plaintext: 64 bytes of zeros (first block)
    plaintext = uint8(zeros(1, 64));

    %% Build 110-byte packet
    header = uint8(hex2dec('AA'));
    data_bytes = [header, key, nonce, plaintext];  % 1+32+12+64 = 109 bytes

    % XOR checksum over all 109 data bytes
    checksum = uint8(0);
    for i = 1:length(data_bytes)
        checksum = bitxor(checksum, data_bytes(i));
    end
    packet = [data_bytes, checksum];  % 110 bytes total

    fprintf('Packet size: %d bytes\n', length(packet));
    fprintf('Checksum: 0x%02X\n', checksum);

    %% Open serial port
    fprintf('Opening %s at %d baud...\n', port_name, baud_rate);
    s = serialport(port_name, baud_rate, 'Timeout', 5);
    configureTerminator(s, 'LF');  % Not used for binary, but required
    cleanup = onCleanup(@() delete(s));

    % Flush any stale data
    flush(s);

    %% Send packet
    fprintf('Sending 110-byte packet...\n');
    write(s, packet, 'uint8');

    %% Read 80-byte response (64B ciphertext + 16B tag)
    fprintf('Waiting for 80-byte response (5s timeout)...\n');
    response = read(s, 80, 'uint8');

    if length(response) ~= 80
        fprintf('ERROR: Expected 80 bytes, got %d\n', length(response));
        return;
    end

    ciphertext = response(1:64);
    tag = response(65:80);

    %% Display results
    fprintf('\n=== Ciphertext (64 bytes) ===\n');
    print_hex_block(ciphertext, 16);

    fprintf('\n=== Poly1305 Tag (16 bytes) ===\n');
    print_hex_block(tag, 16);

    %% Verify against known-good values (from GHDL simulation)
    % These are the expected outputs for key=00..1F, nonce=0..004A..00, plaintext=zeros
    % ChaCha20 counter=1 keystream XOR zeros = keystream itself
    % Update these values from your passing GHDL simulation output
    % Known-good values from GHDL tb_chacha20_top simulation (RFC 8439 test vector)
    expected_cipher_hex = ['224F51F3401BD9E12FDE276FB8631DED' ...
                           '8C131F823D2C06E27E4FCAEC9EF3CF78' ...
                           '8A3B0AA372600A92B57974CDED2B9334' ...
                           '794CBA40C63E34CDEA212C4CF07D41B7'];
    expected_tag_hex    = 'C6252E9A0A47711F9B0A26D9B516A4D1';

    if ~isempty(expected_cipher_hex)
        expected_cipher = hex_to_bytes(expected_cipher_hex);
        if isequal(ciphertext, expected_cipher)
            fprintf('\nCiphertext: PASS\n');
        else
            fprintf('\nCiphertext: FAIL\n');
            fprintf('First mismatch at byte %d\n', find(ciphertext ~= expected_cipher, 1));
        end
    else
        fprintf('\nCiphertext: SKIP (no expected value configured)\n');
    end

    if ~isempty(expected_tag_hex)
        expected_tag = hex_to_bytes(expected_tag_hex);
        if isequal(tag, expected_tag)
            fprintf('Tag: PASS\n');
        else
            fprintf('Tag: FAIL\n');
            fprintf('First mismatch at byte %d\n', find(tag ~= expected_tag, 1));
        end
    else
        fprintf('Tag: SKIP (no expected value configured)\n');
    end

    fprintf('\nDone.\n');
end

%% Helper: print hex block with line breaks
function print_hex_block(data, cols)
    for i = 1:length(data)
        fprintf('%02X ', data(i));
        if mod(i, cols) == 0
            fprintf('\n');
        end
    end
    if mod(length(data), cols) ~= 0
        fprintf('\n');
    end
end

%% Helper: convert hex string to uint8 array
function bytes = hex_to_bytes(hex_str)
    hex_str = strrep(hex_str, ' ', '');
    hex_str = strrep(hex_str, ':', '');
    n = length(hex_str) / 2;
    bytes = uint8(zeros(1, n));
    for i = 1:n
        bytes(i) = uint8(hex2dec(hex_str(2*i-1:2*i)));
    end
end
