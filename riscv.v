

module tang_nano_9k_riscv_monitor
(
  input clk_27mhz,
  input button_s1,
  input uart_rx,
  output [6-1:0] led,
  output uart_tx
);

  // Reset signal control
  wire rst;
  wire running;
  assign rst = ~button_s1;
  assign running = ~rst;

  // rx signals and controls
  wire rx_bsy;

  // tx signals and controls
  wire tx_bsy;

  // LED assigns. In this board the leds are activated by 0 signal
  // led[0] = rx
  // led[1] = rx_bsy
  // led[2] = tx
  // led[3] = tx_bsy
  // led[4] = rst
  // led[5] = desligado
  assign led[0] = uart_rx;
  assign led[1] = ~rx_bsy;
  assign led[2] = uart_tx;
  assign led[3] = ~tx_bsy;
  assign led[4] = ~rst;
  assign led[5] = ~running;

  // I/O data protocol controller

  io_riscv_controller
  io_riscv_controller
  (
    .clk(clk_27mhz),
    .rst(~button_s1),
    .rx(uart_rx),
    .tx(uart_tx)
  );


endmodule



module io_riscv_controller
(
  input clk,
  input rst,
  input rx,
  output tx
);

  reg sw_rst;
  reg sw_clk;

  // Instantiate the RX controller
  wire rx_bsy;
  wire rx_block_timeout;
  wire rx_data_valid;
  wire [8-1:0] rx_data_out;

  // Instantiate the TX controller
  reg send_trig;
  reg [8-1:0] send_data;
  wire tx_bsy;

  // Instantiate the RX fifo
  wire rx_fifo_we;
  wire [8-1:0] rx_fifo_in_data;
  reg rx_fifo_re;
  wire rx_fifo_out_valid;
  wire [8-1:0] rx_fifo_out_data;
  wire rx_fifo_empty;
  // The Rx fifo is controlled by the uart_rx module
  assign rx_fifo_we = rx_data_valid;
  assign rx_fifo_in_data = rx_data_out;

  // PC to board protocol
  localparam [8-1:0] PROT_PC_B_RESET = 8'h0;
  localparam [8-1:0] PROT_PC_B_SEND_CONFIG = 8'h1;
  localparam [8-1:0] PROT_PC_B_CLOCK = 8'h2;

  // Board to PC protocol
  localparam [8-1:0] PROT_B_PC_SEND_DATA = 8'h0;

  // IO and protocol controller
  reg [8-1:0] fsm_io_send_data;
  reg [4-1:0] fsm_io;
  localparam [4-1:0] FSM_IDLE = 4'h0;
  localparam [4-1:0] FSM_DECODE_PROTOCOL = 4'h1;
  localparam [4-1:0] FSM_RESET = 4'h2;
  localparam [4-1:0] FSM_RECEIVE_CONFIG = 4'h3;
  localparam [4-1:0] FSM_EXEC_CLOCK = 4'h4;
  localparam [4-1:0] FSM_SEND_DATA = 4'h5;
  reg [8-1:0] counter;

  always @(posedge clk) begin
    if(rst) begin
      fsm_io <= FSM_IDLE;
      rx_fifo_re <= 1'b0;
      sw_rst <= 1'b1;
      sw_clk <= 1'b0;
      send_trig <= 1'b0;
      counter <= 8'd0;
    end else begin
      rx_fifo_re <= 1'b0;
      sw_rst <= 1'b1;
      sw_clk <= 1'b0;
      send_trig <= 1'b0;
      case(fsm_io)
        FSM_IDLE: begin
          if(~rx_fifo_empty) begin
            rx_fifo_re <= 1'b1;
            fsm_io <= FSM_DECODE_PROTOCOL;
          end 
        end
        FSM_DECODE_PROTOCOL: begin
          if(rx_fifo_out_valid) begin
            case(rx_fifo_out_data)
              PROT_PC_B_RESET: begin
                fsm_io <= FSM_RESET;
              end
              PROT_PC_B_SEND_CONFIG: begin
                fsm_io <= FSM_IDLE;
              end
              PROT_PC_B_CLOCK: begin
                fsm_io <= FSM_EXEC_CLOCK;
              end
              default: begin
                fsm_io <= FSM_IDLE;
              end
            endcase
          end 
        end
        FSM_RESET: begin
          sw_rst <= 1'b0;
          fsm_io <= FSM_IDLE;
        end
        FSM_EXEC_CLOCK: begin
          sw_clk <= 1'b1;
          fsm_io <= FSM_SEND_DATA;
        end
        FSM_SEND_DATA: begin
          if(~tx_bsy) begin
            counter <= counter + 8'd1;
            send_trig <= 1;
            send_data <= counter;
            fsm_io <= FSM_IDLE;
          end 
        end
        default: begin
          fsm_io <= FSM_IDLE;
        end
      endcase
    end
  end


  fifo
  #(
    .FIFO_WIDTH(8),
    .FIFO_DEPTH_BITS(5)
  )
  rx_fifo
  (
    .clk(clk),
    .rst(rst),
    .we(rx_fifo_we),
    .in_data(rx_fifo_in_data),
    .re(rx_fifo_re),
    .out_valid(rx_fifo_out_valid),
    .out_data(rx_fifo_out_data),
    .empty(rx_fifo_empty)
  );


  uart_rx
  uart_rx
  (
    .clk(clk),
    .rst(rst),
    .rx(rx),
    .rx_bsy(rx_bsy),
    .block_timeout(rx_block_timeout),
    .data_valid(rx_data_valid),
    .data_out(rx_data_out)
  );


  uart_tx
  uart_tx
  (
    .clk(clk),
    .rst(rst),
    .send_trig(send_trig),
    .send_data(send_data),
    .tx(tx),
    .tx_bsy(tx_bsy)
  );


  initial begin
    sw_rst = 1;
    sw_clk = 0;
    send_trig = 0;
    send_data = 0;
    rx_fifo_re = 0;
    fsm_io_send_data = 0;
    fsm_io = 0;
    counter = 0;
  end


endmodule



module fifo #
(
  parameter FIFO_WIDTH = 32,
  parameter FIFO_DEPTH_BITS = 2,
  parameter FIFO_ALMOSTFULL_THRESHOLD = 2 ** FIFO_DEPTH_BITS - 2,
  parameter FIFO_ALMOSTEMPTY_THRESHOLD = 2
)
(
  input clk,
  input rst,
  input we,
  input [FIFO_WIDTH-1:0] in_data,
  input re,
  output reg out_valid,
  output reg [FIFO_WIDTH-1:0] out_data,
  output reg empty,
  output reg almostempty,
  output reg full,
  output reg almostfull,
  output reg [FIFO_DEPTH_BITS+1-1:0] data_count
);

  reg [FIFO_DEPTH_BITS-1:0] read_pointer;
  reg [FIFO_DEPTH_BITS-1:0] write_pointer;
  reg [FIFO_WIDTH-1:0] mem [0:2**FIFO_DEPTH_BITS-1];

  always @(posedge clk) begin
    if(rst) begin
      empty <= 1;
      almostempty <= 1;
      full <= 0;
      almostfull <= 0;
      read_pointer <= 0;
      write_pointer <= 0;
      data_count <= 0;
    end else begin
      case({ we, re })
        3: begin
          read_pointer <= read_pointer + 1;
          write_pointer <= write_pointer + 1;
        end
        2: begin
          if(~full) begin
            write_pointer <= write_pointer + 1;
            data_count <= data_count + 1;
            empty <= 0;
            if(data_count == FIFO_ALMOSTEMPTY_THRESHOLD - 1) begin
              almostempty <= 0;
            end 
            if(data_count == 2 ** FIFO_DEPTH_BITS - 1) begin
              full <= 1;
            end 
            if(data_count == FIFO_ALMOSTFULL_THRESHOLD - 1) begin
              almostfull <= 1;
            end 
          end 
        end
        1: begin
          if(~empty) begin
            read_pointer <= read_pointer + 1;
            data_count <= data_count - 1;
            full <= 0;
            if(data_count == FIFO_ALMOSTFULL_THRESHOLD) begin
              almostfull <= 0;
            end 
            if(data_count == 1) begin
              empty <= 1;
            end 
            if(data_count == FIFO_ALMOSTEMPTY_THRESHOLD) begin
              almostempty <= 1;
            end 
          end 
        end
      endcase
    end
  end


  always @(posedge clk) begin
    if(rst) begin
      out_valid <= 0;
    end else begin
      out_valid <= 0;
      if(we == 1) begin
        mem[write_pointer] <= in_data;
      end 
      if(re == 1) begin
        out_data <= mem[read_pointer];
        out_valid <= 1;
      end 
    end
  end


endmodule



module uart_rx
(
  input clk,
  input rst,
  input rx,
  output reg rx_bsy,
  output reg block_timeout,
  output reg data_valid,
  output reg [8-1:0] data_out
);

  // 27MHz
  // 3Mbits
  localparam CLKPERFRM = 86;
  // bit order is lsb-msb
  localparam TBITAT = 5;
  // START BIT
  localparam BIT0AT = 11;
  localparam BIT1AT = 20;
  localparam BIT2AT = 29;
  localparam BIT3AT = 38;
  localparam BIT4AT = 47;
  localparam BIT5AT = 56;
  localparam BIT6AT = 65;
  localparam BIT7AT = 74;
  localparam PBITAT = 80;
  // STOP bit
  localparam BLK_TIMEOUT = 20;
  // this depends on your USB UART chip

  // rx flow control
  reg [8-1:0] rx_cnt;

  //logic rx_sync
  reg rx_hold;
  reg timeout;
  wire frame_begin;
  wire frame_end;
  wire start_invalid;
  wire stop_invalid;

  always @(posedge clk) begin
    if(rst) begin
      rx_hold <= 1'b0;
    end else begin
      rx_hold <= rx;
    end
  end

  // negative edge detect
  assign frame_begin = &{ ~rx_bsy, ~rx, rx_hold };
  // final count
  assign frame_end = &{ rx_bsy, rx_cnt == CLKPERFRM };
  // START bit must be low  for 80% of the bit duration
  assign start_invalid = &{ rx_bsy, rx_cnt < TBITAT, rx };
  // STOP  bit must be high for 80% of the bit duration
  assign stop_invalid = &{ rx_bsy, rx_cnt > PBITAT, ~rx };

  always @(posedge clk) begin
    if(rst) begin
      rx_bsy <= 1'b0;
    end else begin
      if(frame_begin) begin
        rx_bsy <= 1'b1;
      end else if(|{ start_invalid, stop_invalid }) begin
        rx_bsy <= 1'b0;
      end else if(frame_end) begin
        rx_bsy <= 1'b0;
      end 
    end
  end

  // count if frame is valid or until the timeout

  always @(posedge clk) begin
    if(rst) begin
      rx_cnt <= 8'd0;
    end else begin
      if(frame_begin) begin
        rx_cnt <= 8'd0;
      end else if(|{ start_invalid, stop_invalid, frame_end }) begin
        rx_cnt <= 8'd0;
      end else if(~timeout) begin
        rx_cnt <= rx_cnt + 1;
      end else begin
        rx_cnt <= 8'd0;
      end
    end
  end

  // this just stops the rx_cnt

  always @(posedge clk) begin
    if(rst) begin
      timeout <= 1'b0;
    end else begin
      if(frame_begin) begin
        timeout <= 1'b0;
      end else if(&{ ~rx_bsy, rx_cnt == BLK_TIMEOUT }) begin
        timeout <= 1'b1;
      end 
    end
  end

  // this signals the end of block uart transfer

  always @(posedge clk) begin
    if(rst) begin
      block_timeout <= 1'b0;
    end else begin
      if(&{ ~rx_bsy, rx_cnt == BLK_TIMEOUT }) begin
        block_timeout <= 1'b1;
      end else begin
        block_timeout <= 1'b0;
      end
    end
  end

  // this pulses upon completion of a clean frame

  always @(posedge clk) begin
    if(rst) begin
      data_valid <= 1'b0;
    end else begin
      if(frame_end) begin
        data_valid <= 1'b1;
      end else begin
        data_valid <= 1'b0;
      end
    end
  end

  // rx data control

  always @(posedge clk) begin
    if(rst) begin
      data_out <= 8'd0;
    end else begin
      if(rx_bsy) begin
        case(rx_cnt)
          BIT0AT: begin
            data_out[0] <= rx;
          end
          BIT1AT: begin
            data_out[1] <= rx;
          end
          BIT2AT: begin
            data_out[2] <= rx;
          end
          BIT3AT: begin
            data_out[3] <= rx;
          end
          BIT4AT: begin
            data_out[4] <= rx;
          end
          BIT5AT: begin
            data_out[5] <= rx;
          end
          BIT6AT: begin
            data_out[6] <= rx;
          end
          BIT7AT: begin
            data_out[7] <= rx;
          end
        endcase
      end 
    end
  end


  initial begin
    rx_bsy = 0;
    block_timeout = 0;
    data_valid = 0;
    data_out = 0;
    rx_cnt = 0;
    rx_hold = 0;
    timeout = 0;
  end


endmodule



module uart_tx
(
  input clk,
  input rst,
  input send_trig,
  input [8-1:0] send_data,
  output reg tx,
  output reg tx_bsy
);

  // 27MHz
  // 3Mbps
  localparam CLKPERFRM = 90;
  // bit order is lsb-msb
  localparam TBITAT = 1;
  // START bit
  localparam BIT0AT = 10;
  localparam BIT1AT = 19;
  localparam BIT2AT = 28;
  localparam BIT3AT = 37;
  localparam BIT4AT = 46;
  localparam BIT5AT = 55;
  localparam BIT6AT = 64;
  localparam BIT7AT = 73;
  localparam PBITAT = 82;
  // STOP bit

  // tx flow control 
  reg [8-1:0] tx_cnt;

  // buffer
  reg [8-1:0] data2send;
  wire frame_begin;
  wire frame_end;
  assign frame_begin = &{ send_trig, ~tx_bsy };
  assign frame_end = &{ tx_bsy, tx_cnt == CLKPERFRM };

  always @(posedge clk) begin
    if(rst) begin
      tx_bsy <= 1'b0;
    end else begin
      if(frame_begin) begin
        tx_bsy <= 1'b1;
      end else if(frame_end) begin
        tx_bsy <= 1'b0;
      end 
    end
  end


  always @(posedge clk) begin
    if(rst) begin
      tx_cnt <= 8'd0;
    end else begin
      if(frame_end) begin
        tx_cnt <= 8'd0;
      end else if(tx_bsy) begin
        tx_cnt <= tx_cnt + 1;
      end 
    end
  end


  always @(posedge clk) begin
    if(rst) begin
      data2send <= 8'd0;
    end else begin
      data2send <= send_data;
    end
  end


  always @(posedge clk) begin
    if(rst) begin
      tx <= 1'b1;
    end else begin
      if(tx_bsy) begin
        case(tx_cnt)
          TBITAT: begin
            tx <= 1'b0;
          end
          BIT0AT: begin
            tx <= data2send[0];
          end
          BIT1AT: begin
            tx <= data2send[1];
          end
          BIT2AT: begin
            tx <= data2send[2];
          end
          BIT3AT: begin
            tx <= data2send[3];
          end
          BIT4AT: begin
            tx <= data2send[4];
          end
          BIT5AT: begin
            tx <= data2send[5];
          end
          BIT6AT: begin
            tx <= data2send[6];
          end
          BIT7AT: begin
            tx <= data2send[7];
          end
          PBITAT: begin
            tx <= 1'b0;
          end
        endcase
      end else begin
        tx <= 1'b1;
      end
    end
  end


  initial begin
    tx = 1;
    tx_bsy = 0;
    tx_cnt = 0;
    data2send = 0;
  end


endmodule

