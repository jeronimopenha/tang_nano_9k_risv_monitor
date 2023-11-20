

module serial_results
(
  input clk_27mhz,
  input button_s1,
  input uart_rx,
  output [6-1:0] led,
  output uart_tx
);

  // Reset signal control
  wire rst;
  assign rst = ~button_s1;

  wire rx_data_valid;
  wire [8-1:0] rx_data_out;

  wire tx_bsy;

  assign led = 6'b111111;

  reg [8-1:0] sum;
  reg [8-1:0] max;

  reg send_trig;
  reg [8-1:0] send_data;

  reg start;
  reg [8-1:0] n_data;
  reg [9-1:0] counter_rec_data;

  reg [3-1:0] fsm_controller;
  localparam FSM_IDLE = 3'd0;
  localparam FSM_READ_DATA = 3'd1;
  localparam FSM_SEND_SUM = 3'd2;
  localparam FSM_SEND_MAX = 3'd3;

  always @(posedge clk_27mhz) begin
    if(rst) begin
      send_trig <= 1'b0;
      start <= 1'b0;
      fsm_controller <= FSM_IDLE;
    end else begin
      send_trig <= 1'b0;
      case(fsm_controller)
        FSM_IDLE: begin
          start <= 1'b0;
          if(rx_data_valid) begin
            n_data <= rx_data_out;
            counter_rec_data <= 9'd0;
            start <= 1'b1;
            fsm_controller <= FSM_READ_DATA;
          end 
        end
        FSM_READ_DATA: begin
          if(rx_data_valid) begin
            if(counter_rec_data == n_data - 1) begin
              fsm_controller <= FSM_SEND_SUM;
            end else begin
              counter_rec_data <= counter_rec_data + 9'd1;
            end
          end 
        end
        FSM_SEND_SUM: begin
          if(~tx_bsy && ~send_trig) begin
            send_data <= sum;
            send_trig <= 1'b1;
            fsm_controller <= FSM_SEND_MAX;
          end 
        end
        FSM_SEND_MAX: begin
          if(~tx_bsy && ~send_trig) begin
            send_data <= max;
            send_trig <= 1'b1;
            fsm_controller <= FSM_IDLE;
          end 
        end
      endcase
    end
  end

  // somatorio

  always @(posedge clk_27mhz) begin
    if(start) begin
      if(rx_data_valid) begin
        sum <= sum + rx_data_out;
      end 
    end else begin
      sum <= 8'd0;
    end
  end

  // maior

  always @(posedge clk_27mhz) begin
    if(start) begin
      if(rx_data_valid) begin
        if(rx_data_out > max) begin
          max <= rx_data_out;
        end 
      end 
    end else begin
      max <= 8'd0;
    end
  end



  m_uart_rx
  m_uart_rx
  (
    .clk(clk_27mhz),
    .rst(rst),
    .rx(uart_rx),
    .data_valid(rx_data_valid),
    .data_out(rx_data_out)
  );


  m_uart_tx
  m_uart_tx
  (
    .clk(clk_27mhz),
    .rst(rst),
    .send_trig(send_trig),
    .send_data(send_data),
    .tx(uart_tx),
    .tx_bsy(tx_bsy)
  );


  initial begin
    sum = 0;
    max = 0;
    send_trig = 0;
    send_data = 0;
    start = 0;
    n_data = 0;
    counter_rec_data = 0;
    fsm_controller = 0;
  end


endmodule



module m_uart_rx
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


endmodule



module m_uart_tx
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

