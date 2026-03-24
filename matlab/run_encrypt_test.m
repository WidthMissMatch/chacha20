%% run_encrypt_test.m
% ChaCha20-Poly1305 hardware encryption test using RFC 8439 Section 2.4.2 test vector.
%
% Usage:
%   run_encrypt_test                        % uses /dev/ttyUSB0, 115200 baud
%   run_encrypt_test('/dev/ttyUSB0')
%   run_encrypt_test('COM3', 115200)
%
% Requires: fpga_uart_protocol.m in the same directory (or on MATLAB path).
%
% Expected ciphertext (RFC 8439 §2.4.2, 64 zeros encrypted with counter=1):
%   224F51F3 401BD9E1 2FDE276F B8631DED
%   8C131F82 3D2C06E2 7E4FCAEC 9EF3CF78
%   8A3B0AA3 72600A92 B57974CD ED2B9334
%   794CBA40 C63E34CD EA212C4C F07D41B7
%
% Expected Poly1305 tag:
%   C6252E9A 0A47711F 9B0A26D9 B516A4D1

function run_encrypt_test(port_name, baud_rate)
    if nargin < 1, port_name = '/dev/ttyUSB0'; end
    if nargin < 2, baud_rate = 115200; end

    %% RFC 8439 Section 2.4.2 test vector
    key       = uint8(0:31);                               % 00 01 02 ... 1F
    nonce     = uint8([0 0 0 0  0 0 0 hex2dec('4A')  0 0 0 0]);  % 000...004A...00
    plaintext = uint8(zeros(1, 64));                       % 64 zero bytes

    %% Known-good expected outputs (from passing GHDL simulation)
    EXPECTED_CT_HEX = ['224F51F3401BD9E12FDE276FB8631DED' ...
                       '8C131F823D2C06E27E4FCAEC9EF3CF78' ...
                       '8A3B0AA372600A92B57974CDED2B9334' ...
                       '794CBA40C63E34CDEA212C4CF07D41B7'];
    EXPECTED_TAG_HEX = 'C6252E9A0A47711F9B0A26D9B516A4D1';

    expected_ct  = fpga_uart_protocol.hex_to_bytes(EXPECTED_CT_HEX);
    expected_tag = fpga_uart_protocol.hex_to_bytes(EXPECTED_TAG_HEX);

    %% Build packet and communicate with FPGA
    fprintf('=== ChaCha20-Poly1305 Encrypt Test (RFC 8439 §2.4.2) ===\n');
    pkt = fpga_uart_protocol.build_encrypt_packet(key, nonce, plaintext);
    fprintf('Packet: %d bytes, checksum: 0x%02X\n', numel(pkt), pkt(end));

    port = fpga_uart_protocol.open(port_name, baud_rate);
    cleanup = onCleanup(@() fpga_uart_protocol.close(port));

    fprintf('Sending encrypt packet...\n');
    fpga_uart_protocol.send(port, pkt);

    fprintf('Waiting for 80-byte response...\n');
    [ct, tag] = fpga_uart_protocol.recv_encrypt(port);

    %% Display and verify
    fpga_uart_protocol.print_hex('Ciphertext', ct);
    fpga_uart_protocol.print_hex('Poly1305 Tag', tag);

    ct_pass  = isequal(ct,  expected_ct);
    tag_pass = isequal(tag, expected_tag);

    fprintf('\n--- Verification ---\n');
    if ct_pass
        fprintf('Ciphertext : PASS\n');
    else
        fprintf('Ciphertext : FAIL (first mismatch at byte %d)\n', ...
                find(ct ~= expected_ct, 1));
    end
    if tag_pass
        fprintf('Tag        : PASS\n');
    else
        fprintf('Tag        : FAIL (first mismatch at byte %d)\n', ...
                find(tag ~= expected_tag, 1));
    end

    if ct_pass && tag_pass
        fprintf('\n=== ALL TESTS PASSED ===\n');
    else
        error('One or more verification checks FAILED.');
    end
end
