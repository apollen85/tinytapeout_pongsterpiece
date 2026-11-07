library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- TinyTapeout-pinout VGA bouncing-ball demo.
-- A 32x32 white square bounces around the 640x480 visible area, updating
-- position once per frame.
--
-- ui_in[0]   : pause animation
-- ui_in[3:1] : ball colour (R, G, B bit each)
-- ui_in[5:4] : paddle1 up/down
-- ui_in[7:6] : paddle2 up/down
--
-- Inspired by the classic 'first VGA sprite' pattern from FPGA tutorials
-- (Mike Field, Nandland). Original implementation for VHDLive.
entity tt_um_pongsterpiece is
  port (
    clk    : in  std_logic;
    rst_n  : in  std_logic;
    ena    : in std_logic;
    ui_in  : in  std_logic_vector(7 downto 0);
    uo_out : out std_logic_vector(7 downto 0);
    uio_in  : in  std_logic_vector(7 downto 0);
    uio_out : out std_logic_vector(7 downto 0);
    uio_oe  : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of tt_um_pongsterpiece is
  constant H_ACT : natural := 640;
  constant V_ACT : natural := 480;
  constant BALL_SIZE  : natural := 32;
  constant BALL_STEP_SIZE : natural := 2;
  constant PADDLE_WIDTH : natural := 16;
  constant PADDLE_HEIGHT : natural := 128;
  constant PADDLE_EDGE_OFFSET : natural := 32;
  constant PADDLE_STEP_SIZE : natural := 3;

  -- Ball parameters
  constant BALL_START_X : unsigned(9 downto 0) := to_unsigned(H_ACT/2 - BALL_SIZE/2, 10);
  constant BALL_START_Y : unsigned(9 downto 0) := to_unsigned(V_ACT/2 - BALL_SIZE/2, 10);

  -- Paddle 1 parameters
  constant PADDLE1_START_X : unsigned(9 downto 0) := to_unsigned( PADDLE_EDGE_OFFSET - PADDLE_WIDTH/2, 10);
  constant PADDLE1_START_Y : unsigned(9 downto 0) := to_unsigned(V_ACT/2 - PADDLE_HEIGHT/2, 10);


  -- Paddle 2 parameters
  constant PADDLE2_START_X : unsigned(9 downto 0) := to_unsigned( H_ACT - PADDLE_EDGE_OFFSET - PADDLE_WIDTH/2, 10);
  constant PADDLE2_START_Y : unsigned(9 downto 0) := to_unsigned(V_ACT/2 - PADDLE_HEIGHT/2, 10);

  signal hpos : unsigned(9 downto 0) := (others => '0');
  signal vpos : unsigned(9 downto 0) := (others => '0');
  signal hsync, vsync, vis : std_logic;

  -- Ball top-left position in active-area coords
  signal bx : unsigned(9 downto 0) := BALL_START_X;
  signal by : unsigned(9 downto 0) := BALL_START_Y;
  -- Velocity sign: '0' = moving right/down, '1' = moving left/up
  --Velocity : positive = moving right/down, negative = moving left/up
  signal vx : unsigned(1 downto 0) := to_unsigned(2, 2);
  signal vx_sign : std_logic := '0';
  signal vy : unsigned(1 downto 0) := to_unsigned(2, 2);
  signal vy_sign : std_logic := '0';


  signal last_vsync : std_logic := '1';

  -- Paddle 1 top-left position in active-area coords
  constant pdl1x : unsigned(9 downto 0) := PADDLE1_START_X;
  signal pdl1y : unsigned(9 downto 0) := PADDLE1_START_Y;

  -- Paddle 2 top-left position in active-area coords
  constant pdl2x : unsigned(9 downto 0) := PADDLE2_START_X;
  signal pdl2y : unsigned(9 downto 0) := PADDLE2_START_Y;

  signal r, g, b : unsigned(1 downto 0);

  signal game_over : std_logic := '0';
  signal game_start_counter : unsigned(7 downto 0) := to_unsigned(0, 8);
  constant GAME_START_DELAY : unsigned(7 downto 0) := to_unsigned(90, 8);

  type sprite_t is array (0 to 7) of std_logic_vector(7 downto 0);
  constant SKULL : sprite_t := (
      "00000000",
      "01111100",
      "10000010",
      "10101010",
      "10000010",
      "01010100",
      "01010100",
      "00000000"
  );
  constant SKULL_SCALE : natural := 32;
  constant SKULL_SIZE : natural := 8;
  constant SKULL_WIDTH : natural := SKULL_SIZE * SKULL_SCALE;
  constant SKULL_POS_X : natural := H_ACT/2;
  constant SKULL_POS_Y : natural := V_ACT/2;


begin

uio_out <= (others => '0');
uio_oe  <= (others => '0');

  -- ── VGA pixel counter ────────────────────────────────────────────────────
  process(clk, rst_n) is
  begin
    if rst_n = '0' then
      hpos <= (others => '0');
      vpos <= (others => '0');
    elsif rising_edge(clk) then
      if hpos = 799 then
        hpos <= (others => '0');
        if vpos = 524 then vpos <= (others => '0');
        else               vpos <= vpos + 1;
        end if;
      else hpos <= hpos + 1;
      end if;
    end if;
  end process;

  hsync <= '0' when hpos < 96 else '1';
  vsync <= '0' when vpos < 2  else '1';
  vis   <= '1' when hpos >= 144 and hpos < 784 and vpos >= 35 and vpos < 515 else '0';

  -- ── Ball and paddle physics: advance once per frame on vsync falling edge ───────────
  process(clk, rst_n) is
    variable impact_zone : integer range 0 to 7;
  begin
    if rst_n = '0' then
      bx <= BALL_START_X;
      by <= BALL_START_Y;
      vx <= to_unsigned(2, 2);
      vx_sign <= '0';
      vy <= to_unsigned(2, 2);
      vy_sign <= '0';
      pdl1y <= PADDLE1_START_Y;
      pdl2y <= PADDLE2_START_Y;
      game_over <= '0';
      game_start_counter <= to_unsigned(0, 8);
      last_vsync <= '1';
    elsif rising_edge(clk) then
      last_vsync <= vsync;
      if last_vsync = '1' and vsync = '0' and ui_in(0) = '0' then
        -- game over countdown
        if game_over = '1' then
          if game_start_counter >= GAME_START_DELAY then
            game_over <= '0';
            game_start_counter <= to_unsigned(0, 8);
            vx <= to_unsigned(2, 2);
            vy <= to_unsigned(2, 2);
            vx_sign <= '0';
            vy_sign <= '1';
            bx <= BALL_START_X;
            by <= BALL_START_Y;
          else
            game_start_counter <= game_start_counter + 1;
          end if;
        else
          -- BALL LOGIC ====================================================================
          -- Vertical step
          if (vy_sign = '0' and by +BALL_SIZE >= V_ACT - 1) or (vy_sign = '1' and by = 0) then
            vy_sign <= not vy_sign;
          end if;
          -- Horizontal step
          -- Collision with paddle2 (right)
          if vx_sign = '0' and
              bx + BALL_SIZE >= pdl2x and
              bx <= pdl2x + PADDLE_WIDTH and
              by + BALL_SIZE >= pdl2y and
              by <= pdl2y + PADDLE_HEIGHT then

              impact_zone := (to_integer(by)+BALL_SIZE/2-to_integer(pdl2y)) *8/PADDLE_HEIGHT;

              case impact_zone is
                when 0 =>
                  vx <= to_unsigned(1, 2);
                  vy <= to_unsigned(2, 2);
                when 7 =>
                  vx <= to_unsigned(1, 2);
                  vy <= to_unsigned(2, 2);
                when 3 =>
                  vx <= to_unsigned(3, 2);
                  vy <= to_unsigned(2, 2);
                when 4 =>
                  vx <= to_unsigned(3, 2);
                  vy <= to_unsigned(2, 2);
                when others =>
                  vx <= to_unsigned(2, 2);
                  vy <= to_unsigned(2, 2);
              end case;

              vx_sign <= not vx_sign;

              if ui_in(7) = '1' then -- go up
                vy_sign <= '1';
              elsif ui_in(6) = '1' then -- go down
                vy_sign <= '0';
              end if;
          -- Collision with paddle1 (left)
          elsif vx_sign = '1' and
              bx >= pdl1x and
              bx <= pdl1x + PADDLE_WIDTH and
              by + BALL_SIZE >= pdl1y and
              by <= pdl1y + PADDLE_HEIGHT then

              impact_zone := (to_integer(by)+BALL_SIZE/2-to_integer(pdl1y)) *8/PADDLE_HEIGHT;

              case impact_zone is
                when 0 =>
                  vx <= to_unsigned(1, 2);
                  vy <= to_unsigned(2, 2);
                when 7 =>
                  vx <= to_unsigned(1, 2);
                  vy <= to_unsigned(2, 2);
                when 3 =>
                  vx <= to_unsigned(3, 2);
                  vy <= to_unsigned(2, 2);
                when 4 =>
                  vx <= to_unsigned(3, 2);
                  vy <= to_unsigned(2, 2);
                when others =>
                  vx <= to_unsigned(2, 2);
                  vy <= to_unsigned(2, 2);
              end case;

              vx_sign <= not vx_sign;

              if ui_in(5) = '1' then -- go up
                vy_sign <= '1';
              elsif ui_in(4) = '1' then -- go down
                vy_sign <= '0';
              end if;


          end if;
          -- Set coordinates with velocities
          if vx_sign = '0' then
            bx <= bx + vx * BALL_STEP_SIZE;
          else
            bx <= bx - vx * BALL_STEP_SIZE;
          end if;
          if vy_sign = '0' then
            by <= by + vy * BALL_STEP_SIZE;
          else
            by <= by - vy * BALL_STEP_SIZE;
          end if;


          -- Collision with sides (GAME OVER)
          if bx + BALL_SIZE >= H_ACT - 1 - BALL_STEP_SIZE or bx = BALL_STEP_SIZE then
          game_over <= '1';
            bx <= BALL_START_X;
            by <= BALL_START_Y;
            -- stop ball
            vx <= to_unsigned(0,2);
            vy <= to_unsigned(0,2);
          end if;
          
          -- END BALL LOGIC ==============================================================================================
          -- Paddle1 up/down
          if ui_in(5) = '1' and pdl1y >= PADDLE_STEP_SIZE then
            pdl1y <= pdl1y - PADDLE_STEP_SIZE;
          elsif ui_in(4) = '1' and pdl1y+PADDLE_HEIGHT <= V_ACT - PADDLE_STEP_SIZE then
            pdl1y <= pdl1y + PADDLE_STEP_SIZE;
          end if;
          -- Paddle2 up/down
          if ui_in(7) = '1' and pdl2y >= PADDLE_STEP_SIZE then
            pdl2y <= pdl2y - PADDLE_STEP_SIZE;
          elsif ui_in(6) = '1' and pdl2y + PADDLE_HEIGHT <= V_ACT - PADDLE_STEP_SIZE then
            pdl2y <= pdl2y + PADDLE_STEP_SIZE;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- ── Pixel colour ─────────────────────────────────────────────────────────
  process(vis, hpos, vpos, bx, by, ui_in) is
    variable px : unsigned(9 downto 0);
    variable py : unsigned(9 downto 0);
    variable in_ball : boolean;
    variable in_paddle1 : boolean;
    variable in_paddle2 : boolean;
    variable in_skull : boolean;
    variable skull_x : integer range 0 to 7;
    variable skull_y : integer range 0 to 7;
  begin
    r <= "00"; g <= "00"; b <= "00";
    if vis = '1' then
      px := hpos - 144;
      py := vpos - 35;
      in_ball := (px >= bx) and (px < bx + BALL_SIZE) and (py >= by) and (py < by + BALL_SIZE);
      in_paddle1 := (px >= pdl1x) and (px < pdl1x + PADDLE_WIDTH) and (py >= pdl1y) and (py < pdl1y + PADDLE_HEIGHT);
      in_paddle2 := (px >= pdl2x) and (px < pdl2x + PADDLE_WIDTH) and (py >= pdl2y) and (py < pdl2y + PADDLE_HEIGHT);
      in_skull := (px >= SKULL_POS_X-SKULL_WIDTH/2) and (px < SKULL_POS_X+SKULL_WIDTH/2) and (py >= SKULL_POS_Y-SKULL_WIDTH/2) and (py < SKULL_POS_Y+SKULL_WIDTH/2);
      if in_ball and game_over = '0' then
        r <= ui_in(1) & ui_in(1);
        g <= ui_in(2) & ui_in(2);
        b <= ui_in(3) & ui_in(3);
      elsif in_paddle1 then
        r <= "11";
        g <= "11";
        b <= "11";
      elsif in_paddle2 then
        r <= "11";
        g <= "11";
        b <= "11";
      else
        -- black background
        if game_over = '1' then
          r <= "11";
          g <= "00";
          b <= "00";
        else
          r <= "00";
          g <= "00";
          b <= "00";
        end if;
        if in_skull then
          skull_x := (to_integer(px)-(SKULL_POS_X-SKULL_WIDTH/2)) / SKULL_SCALE;
          skull_y := (to_integer(py)-(SKULL_POS_Y-SKULL_WIDTH/2)) / SKULL_SCALE;
          if SKULL(skull_y)(SKULL_SIZE-1-skull_x) = '1' then
            r <= "00";
            g <= "00";
            b <= "00";
          end if;
        end if;
      end if;

    end if;
  end process;

  uo_out <= hsync & b(0) & g(0) & r(0) & vsync & b(1) & g(1) & r(1);
end architecture;
