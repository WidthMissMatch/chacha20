classdef fpga_uart_protocol
% FPGA_UART_PROTOCOL  Helper class for ChaCha20-Poly1305 UART protocol.
%
% This class provides static methods for building, sending, and receiving
% packets to/from the ZCU106 ChaCha20-Poly1305 FPGA core.
%
% Protocols:
%   Encrypt  (0xAA): [0xAA][32B key][12B nonce][64B plaintext][1B checksum]  = 110B TX
%                    [64B ciphertext][16B Poly1305 tag]                        = 80B RX
%   ECDH     (0xAB): [0xAB][32B priv_key][32B peer_pub][1B checksum]          = 66B TX
%                    [32B shared_secret][32B public_key_out]                   = 64B RX
%
% Usage:
%   port = fpga_uart_protocol.open('/dev/ttyUSB0', 115200);
%   pkt  = fpga_uart_protocol.build_encrypt_packet(key, nonce, plaintext);
%   fpga_uart_protocol.send(port, pkt);
%   [ct, tag] = fpga_uart_protocol.recv_encrypt(port);
%   fpga_uart_protocol.close(port);

    methods (Static)

        % -----------------------------------------------------------------
        function port = open(port_name, baud_rate)
        % OPEN  Open the UART serial port.
            if nargin < 1, port_name = '/dev/ttyUSB0'; end
            if nargin < 2, baud_rate = 115200; end
            port = serialport(port_name, baud_rate, 'Timeout', 10);
            configureTerminator(port, 'LF');
            flush(port);
            fprintf('Opened %s at %d baud.\n', port_name, baud_rate);
        end

        % -----------------------------------------------------------------
        function close(port)
        % CLOSE  Close and delete the serial port object.
            delete(port);
        end

        % -----------------------------------------------------------------
        function send(port, packet)
        % SEND  Write raw bytes to the FPGA.
            write(port, packet, 'uint8');
        end

        % -----------------------------------------------------------------
        function pkt = build_encrypt_packet(key, nonce, plaintext)
        % BUILD_ENCRYPT_PACKET  Assemble a 110-byte 0xAA encrypt packet.
        %
        %   key       : uint8 row vector, 32 bytes
        %   nonce     : uint8 row vector, 12 bytes
        %   plaintext : uint8 row vector, 64 bytes
        %   Returns 110-byte uint8 packet.
            assert(numel(key)       == 32, 'key must be 32 bytes');
            assert(numel(nonce)     == 12, 'nonce must be 12 bytes');
            assert(numel(plaintext) == 64, 'plaintext must be 64 bytes');

            header     = uint8(hex2dec('AA'));
            data_bytes = [header, uint8(key(:)'), uint8(nonce(:)'), uint8(plaintext(:)')];
            checksum   = fpga_uart_protocol.xor_checksum(data_bytes);
            pkt        = [data_bytes, checksum];
        end

        % -----------------------------------------------------------------
        function pkt = build_ecdh_packet(priv_key, peer_pub)
        % BUILD_ECDH_PACKET  Assemble a 66-byte 0xAB ECDH packet.
        %
        %   priv_key : uint8 row vector, 32 bytes (X25519 private key, little-endian)
        %   peer_pub : uint8 row vector, 32 bytes (X25519 peer public key, little-endian)
        %   Returns 66-byte uint8 packet.
            assert(numel(priv_key) == 32, 'priv_key must be 32 bytes');
            assert(numel(peer_pub) == 32, 'peer_pub must be 32 bytes');

            header     = uint8(hex2dec('AB'));
            data_bytes = [header, uint8(priv_key(:)'), uint8(peer_pub(:)')];
            checksum   = fpga_uart_protocol.xor_checksum(data_bytes);
            pkt        = [data_bytes, checksum];
        end

        % -----------------------------------------------------------------
        function [ciphertext, tag] = recv_encrypt(port)
        % RECV_ENCRYPT  Receive 80-byte encrypt response: 64B ciphertext + 16B tag.
            raw = read(port, 80, 'uint8');
            if numel(raw) ~= 80
                error('Expected 80 bytes, got %d', numel(raw));
            end
            ciphertext = raw(1:64);
            tag        = raw(65:80);
        end

        % -----------------------------------------------------------------
        function [shared_secret, public_key] = recv_ecdh(port)
        % RECV_ECDH  Receive 64-byte ECDH response: 32B shared_secret + 32B public_key.
            raw = read(port, 64, 'uint8');
            if numel(raw) ~= 64
                error('Expected 64 bytes, got %d', numel(raw));
            end
            shared_secret = raw(1:32);
            public_key    = raw(33:64);
        end

        % -----------------------------------------------------------------
        function cs = xor_checksum(data)
        % XOR_CHECKSUM  Running XOR of all bytes in data array.
            cs = uint8(0);
            for i = 1:numel(data)
                cs = bitxor(cs, data(i));
            end
        end

        % -----------------------------------------------------------------
        function print_hex(label, data)
        % PRINT_HEX  Pretty-print a byte array as hex.
            fprintf('%s (%d bytes):\n  ', label, numel(data));
            for i = 1:numel(data)
                fprintf('%02X ', data(i));
                if mod(i, 16) == 0 && i < numel(data)
                    fprintf('\n  ');
                end
            end
            fprintf('\n');
        end

        % -----------------------------------------------------------------
        function bytes = hex_to_bytes(hex_str)
        % HEX_TO_BYTES  Convert hex string (with optional spaces/colons) to uint8 array.
            hex_str = regexprep(hex_str, '[^0-9A-Fa-f]', '');
            n = length(hex_str) / 2;
            bytes = uint8(zeros(1, n));
            for i = 1:n
                bytes(i) = uint8(hex2dec(hex_str(2*i-1:2*i)));
            end
        end

    end % methods
end % classdef
