%% run_ecdh_test.m
% X25519 ECDH key exchange hardware test using RFC 7748 Section 6.1 test vector.
%
% Usage:
%   run_ecdh_test                        % uses /dev/ttyUSB0, 115200 baud
%   run_ecdh_test('/dev/ttyUSB0')
%   run_ecdh_test('COM3', 115200)
%
% Requires: fpga_uart_protocol.m in the same directory (or on MATLAB path).
%
% Protocol:
%   TX → FPGA: [0xAB][32B priv_key][32B peer_pub][1B checksum] = 66 bytes
%   RX ← FPGA: [32B shared_secret][32B public_key_out]          = 64 bytes
%
% RFC 7748 §6.1 test vector (all values little-endian byte order):
%   Alice private: 77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a
%   Bob   public:  de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f
%   Expected SS:   4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742

function run_ecdh_test(port_name, baud_rate)
    if nargin < 1, port_name = '/dev/ttyUSB0'; end
    if nargin < 2, baud_rate = 115200; end

    proto = @fpga_uart_protocol;  % shorthand

    %% RFC 7748 §6.1 test vectors (all little-endian byte strings)
    ALICE_PRIV_HEX = '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a';
    BOB_PUB_HEX    = 'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f';
    EXP_SS_HEX     = '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742';

    alice_priv = proto.hex_to_bytes(ALICE_PRIV_HEX);
    bob_pub    = proto.hex_to_bytes(BOB_PUB_HEX);
    expected_ss = proto.hex_to_bytes(EXP_SS_HEX);

    fprintf('=== X25519 ECDH Test (RFC 7748 §6.1) ===\n');
    proto.print_hex('Alice private key', alice_priv);
    proto.print_hex('Bob   public  key', bob_pub);

    %% Send ECDH packet to FPGA
    pkt = proto.build_ecdh_packet(alice_priv, bob_pub);
    fprintf('Packet: %d bytes, checksum: 0x%02X\n', numel(pkt), pkt(end));

    port = proto.open(port_name, baud_rate);
    cleanup = onCleanup(@() proto.close(port));

    fprintf('Sending ECDH packet (0xAB)...\n');
    proto.send(port, pkt);

    fprintf('Waiting for 64-byte response (ECDH takes ~1.7M clocks at 125 MHz ≈ 13.6 ms)...\n');
    [ss, pk] = proto.recv_ecdh(port);

    %% Display and verify
    proto.print_hex('Shared secret',  ss);
    proto.print_hex('Public key out', pk);
    proto.print_hex('Expected SS',    expected_ss);

    fprintf('\n--- Verification ---\n');
    if isequal(ss, expected_ss)
        fprintf('Shared secret: PASS\n');
    else
        idx = find(ss ~= expected_ss, 1);
        fprintf('Shared secret: FAIL (first mismatch at byte %d: got 0x%02X expected 0x%02X)\n', ...
                idx, ss(idx), expected_ss(idx));
    end

    % Note: public_key_out = alice_priv * BASE_U — no RFC reference value shown
    % but we can verify it's non-zero and different from the shared secret
    if any(pk ~= 0) && ~isequal(pk, ss)
        fprintf('Public key   : PLAUSIBLE (non-zero, differs from shared secret)\n');
    else
        fprintf('Public key   : SUSPECT (all zeros or equals shared secret)\n');
    end

    if isequal(ss, expected_ss)
        fprintf('\n=== ECDH TEST PASSED ===\n');
    else
        error('ECDH shared secret mismatch.');
    end
end
