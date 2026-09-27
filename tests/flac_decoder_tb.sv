`timescale 1ns/1ps

module flac_decoder_tb;

logic clk = 1'b0;
logic reset = 1'b1;
logic [7:0] input_data = 0;
logic input_valid = 1'b0;
logic input_ready;
logic input_end = 1'b0;
logic pcm_valid;
logic pcm_ready = 1'b0;
logic signed [15:0] pcm_left;
logic signed [15:0] pcm_right;
logic pcm_eof;
logic format_valid;
logic metadata_valid;
logic [31:0] sample_rate;
logic [35:0] total_samples;
logic format_error;
logic [7:0] error_code;

logic [7:0] flac_bytes [0:262143];
logic [7:0] pcm_bytes [0:262143];
integer flac_size;
integer pcm_size;
integer pcm_count;
integer eof_count;
integer ready_counter;
integer previous_decoder_state;
string vector_dir;

always #5 clk = ~clk;

always @(posedge clk)
    if (!format_error)
        previous_decoder_state <= dut.state;

flac_decoder dut (
    .clk(clk), .reset(reset),
    .input_data(input_data), .input_valid(input_valid),
    .input_ready(input_ready), .input_end(input_end),
    .pcm_valid(pcm_valid), .pcm_ready(pcm_ready),
    .pcm_left(pcm_left), .pcm_right(pcm_right), .pcm_eof(pcm_eof),
    .format_valid(format_valid), .metadata_valid(metadata_valid),
    .sample_rate(sample_rate), .total_samples(total_samples),
    .format_error(format_error), .error_code(error_code)
);

task automatic restart;
begin
    @(negedge clk);
    reset = 1'b1;
    input_valid = 1'b0;
    input_end = 1'b0;
    pcm_ready = 1'b0;
    pcm_count = 0;
    eof_count = 0;
    ready_counter = 0;
    repeat (3) @(negedge clk);
    reset = 1'b0;
end
endtask

task automatic load_file(input string path, input bit load_pcm);
    integer descriptor;
    integer count;
begin
    descriptor = $fopen(path, "rb");
    if (descriptor == 0)
        $fatal(1, "cannot open %s", path);
    if (load_pcm)
        count = $fread(pcm_bytes, descriptor);
    else
        count = $fread(flac_bytes, descriptor);
    $fclose(descriptor);
    if (load_pcm)
        pcm_size = count;
    else
        flac_size = count;
end
endtask

task automatic send_loaded_file;
begin
    for (integer i = 0; i < flac_size; i = i + 1) begin
        @(negedge clk);
        if (format_error)
            break;
        input_data = flac_bytes[i];
        input_valid = 1'b1;
        while (!input_ready && !format_error)
            @(negedge clk);
        if (format_error)
            break;
        @(negedge clk);
        input_valid = 1'b0;
    end
    @(negedge clk);
    input_valid = 1'b0;
    input_end = !format_error;
    @(negedge clk);
    input_end = 1'b0;
end
endtask

task automatic receive_expected_pcm;
    logic signed [15:0] expected_left;
    logic signed [15:0] expected_right;
begin
    while (pcm_count < pcm_size / 4) begin
        @(negedge clk);
        ready_counter = ready_counter + 1;
        pcm_ready = ready_counter % 5 != 0;
        if (pcm_valid && pcm_ready) begin
            expected_left = {pcm_bytes[pcm_count * 4 + 1],
                             pcm_bytes[pcm_count * 4]};
            expected_right = {pcm_bytes[pcm_count * 4 + 3],
                              pcm_bytes[pcm_count * 4 + 2]};
            if (pcm_left !== expected_left || pcm_right !== expected_right)
                $fatal(1, "PCM %0d was %h/%h expected %h/%h",
                    pcm_count, pcm_left, pcm_right, expected_left, expected_right);
            if (pcm_eof)
                eof_count = eof_count + 1;
            pcm_count = pcm_count + 1;
        end
    end
    pcm_ready = 1'b1;
end
endtask

task automatic run_valid(
    input string name,
    input integer expected_rate,
    input integer expected_samples
);
begin
    restart();
    load_file({vector_dir, "/", name, ".flac"}, 1'b0);
    load_file({vector_dir, "/", name, ".raw"}, 1'b1);
    fork
        send_loaded_file();
        receive_expected_pcm();
    join
    repeat (8) @(posedge clk);
    if (format_error || error_code != 0 || !format_valid || !metadata_valid ||
            sample_rate != expected_rate || total_samples != expected_samples ||
            pcm_count != expected_samples || eof_count != 1)
        $fatal(1, "%s status rate=%0d total=%0d pcm=%0d eof=%0d error=%02x",
            name, sample_rate, total_samples, pcm_count, eof_count, error_code);
end
endtask

initial begin
    if (!$value$plusargs("VECTOR_DIR=%s", vector_dir))
        $fatal(1, "VECTOR_DIR plusarg is required");

    run_valid("lpc44", 44100, 5000);
    run_valid("fixed48", 48000, 1152);
    run_valid("constant44", 44100, 192);

    restart();
    load_file({vector_dir, "/profile96.flac"}, 1'b0);
    send_loaded_file();
    repeat (8) @(posedge clk);
    if (!format_error || error_code != 8'h21 || pcm_count != 0)
        $fatal(1, "out-of-profile sample rate was not rejected");

    restart();
    load_file({vector_dir, "/crc-corrupt.flac"}, 1'b0);
    load_file({vector_dir, "/lpc44.raw"}, 1'b1);
    fork
        send_loaded_file();
        begin
            // Only the first 4096-sample frame may be admitted. The final
            // frame's corrupted CRC must prevent all of its PCM from escaping.
            while (!format_error) begin
                @(negedge clk);
                pcm_ready = 1'b1;
                if (pcm_valid) begin
                    if (pcm_count >= 4096)
                        $fatal(1, "CRC-failed frame exposed provisional PCM");
                    pcm_count = pcm_count + 1;
                end
            end
        end
    join
    if (error_code != 8'h23 || pcm_count != 4096)
        $fatal(1, "CRC corruption status=%02x admitted=%0d", error_code, pcm_count);

    $display("PASS FLAC streamable-subset decode, backpressure, profile rejection, and CRC admission");
    $finish;
end

initial begin
    #100_000_000;
    $display("timeout state=%0d previous=%0d substate=%0d input_ready=%0b byte_bits=%0d pcm=%0d frame_size=%0d channel=%0d write_index=%0d bit_field=%h error=%02x",
        dut.state, previous_decoder_state, dut.subframe_decoder.state, input_ready, dut.byte_bits,
        pcm_count, dut.frame_size, dut.sample_channel, dut.write_index,
        dut.bit_field, error_code);
    $fatal(1, "FAIL FLAC decoder timeout");
end

endmodule
