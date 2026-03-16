# -*- coding: utf-8 -*-

# ゲームを実装したクラス
class Game
  MOVING_BLOCK_SPEED = 0.4
  START_CHECKPOINT = {x: 96, y: 50}.freeze
  TIME_LIMIT = 30.0

  CHIP_POS = [
    [nil, nil, nil, nil, :nil, :goal],
    [nil, nil, nil, nil],
    [:block, nil, nil, nil],
    [:checkpoint_block, :active_checkpoint_block, :cracked_block, :moving_block, :moving_block_edge],
    [:spike, :coin, nil, nil],
  ]
  CHIP_OXY_BY_KIND =
    CHIP_POS.each_with_index.with_object({}) do |(row, oy), map|
      row.each_with_index do |kind, ox|
        next unless kind
        map[kind] = [ox * 8, oy * 8]
      end
    end.freeze

  def initialize()
    @current_oy = 0
    # ジャンプをロックするフラグ
    @jump_locked = false
    # 画面を揺らす量
    @shake = 0
    # ゲーム進行状態
    @state = :ready
    # 復帰先チェックポイント（プレイヤー座標）
    @checkpoint = START_CHECKPOINT.dup
    # 残り時間（秒）
    @time_left = TIME_LIMIT
    # 時間計測用の直前時刻
    @last_tick_at = nil
    @score = 0
    @cracked_block_spawns = nil

    size width / 2, height / 2
    cracked_block_spawns

    set_timeout do
      # 全スプライトを追加して物理演算処理用に登録しておく
      [*stage, player].each do
        add_sprite(_1)
      end
    end

    # 重力を (x, y) で設定
    gravity(0, 500)
  end

  def now()
    Time.now.to_f
  end

  def count_down(count = 3, &block)
    if count == 0
      project.sounds[1].play
      @count_down_text = nil
      block.call
    else
      project.sounds[0].play
      @count_down_text = count.to_s
      set_timeout(1) {count_down count - 1, &block}
    end
  end

  def start_game()
    @state = :playing
    @last_tick_at = now
  end

  def restart_from_fall()
    return unless @state == :playing

    @state = :count_down
    @jump_locked = false
    @last_tick_at = nil
    restore_cracked_blocks

    player.x, player.y = @checkpoint.values_at(:x, :y)
    player.vel = Vector.new(0, 0)
    @current_oy = player.y - height / 2

    count_down { start_game }
  end

  def gameover()
    @state = :gameover
    @last_tick_at = nil
  end

  def clear()
    return unless @state == :playing

    @state = :clear
    @last_tick_at = nil
  end

  def reset_to_initial()
    stage.each {remove_sprite(_1)}
    remove_sprite(@player) if @player
    project.clear_all_sprites

    @stage = nil
    @moving_blocks = nil
    @moving_block_edges = nil
    @cracked_block_spawns = nil

    @checkpoint = START_CHECKPOINT.dup
    @time_left = TIME_LIMIT
    @last_tick_at = nil
    @score = 0
    @current_oy = 0
    @shake = 0
    @jump_locked = false
    @count_down_text = nil

    [*stage, player].each {add_sprite(_1)}
    player.x, player.y = @checkpoint.values_at(:x, :y)
    player.vel = Vector.new(0, 0)
  end

  # 描画前にゲームの状態を更新する
  def update()
    moving_blocks
    return unless @state == :playing

    # playing 中だけ時間を減らす
    current = now
    if @last_tick_at
      @time_left -= current - @last_tick_at
      @time_left = 0 if @time_left < 0
    end
    @last_tick_at = current
    return gameover if @time_left <= 0

    # 左右カーソルキーでプレイヤースプライトのx軸方向の速度を更新
    player.vx -= 10 if player.vx > -50 && key_is_down(LEFT)
    player.vx += 10 if player.vx < +50 && key_is_down(RIGHT)

    # プレイヤースプライトの速度を減衰させる
    player.vx *= 0.9

    # 画面を揺らす量を減衰させる
    @shake *= 0.8

    # 画面を揺らす量が十分に小さな値になったらゼロにしておく
    @shake = 0 if @shake < 0.1

    # カメラの表示範囲より下に落ちたらチェックポイントから復帰
    restart_from_fall if player.bottom > (@current_oy + height)
  end

  def draw_hud()
    fill(255)
    text_size(12)

    text_align(LEFT, TOP)
    text(format("Time: %04.1f", @time_left), 4, 4, width, height)

    text_align(RIGHT, TOP)
    text("Score: #{@score.to_i.abs}", 0, 4, width - 4, height)
  end

  def draw_state()
    state_text =
      case @state
      when :ready      then "Press Space"
      when :count_down then @count_down_text
      when :clear      then "Clear!"
      when :gameover   then "Game Over!"
      else return
      end

    fill(255)
    text_size(30)
    text_align(CENTER, CENTER)
    text(state_text, 0, 0, width, height)
  end

  # 秒間60回呼ばれるのでゲーム画面を描画する
  def draw()
    ox = 0
    # 上方向（yが小さくなる方向）にだけ追従し、下方向には戻さない
    @current_oy = [@current_oy, player.y - height / 2].min
    oy = @current_oy
    screenOffset ox, oy

    @score = [@score, @current_oy].min

    # 背景を黒でクリア
    background(0)

    # 画面を揺らす
    if @shake != 0
      shake = Vector.random2D * @shake
      translate(shake.x, shake.y)
    end

    # 座標変換を do-end 後に復帰する
    push do
      # プレイヤーの座標に合わせてX方向の描画位置をずらす
      translate(-ox, -oy)
      # ステージのスプライト、プレイヤーの順に描画する
      sprite(*stage, player)
    end

    draw_hud
    draw_state
  end

  def key_down(key)
    case @state
    when :ready
      return unless key == SPACE
      @state = :count_down
      count_down {start_game}
    when :gameover
      return unless key == SPACE
      reset_to_initial
      @state = :count_down
      count_down {start_game}
    when :playing
      # SPACE キーが押されたら
      if key == SPACE && !@jump_locked
        # 上方向の速度を与えてジャンプ
        @player.vy = -150
        # ジャンプ後は、ブロックに当たるまでジャンプを禁止
        @jump_locked = true
        # 0番目のサウンドを再生する
        project.sounds[0].play
      end
    end
  end

  def stage()
    # ステージ用のマップデータからスプライトを生成
    @stage ||= project.maps[0].sprites
  end

  def cracked_block_spawns()
    @cracked_block_spawns ||= stage
      .select {|sp| chip_kind(sp) == :cracked_block}
      .map {|sp| {x: sp.x, y: sp.y, w: sp.w, h: sp.h, z: sp.z}}
  end

  def restore_cracked_blocks()
    ox, oy = CHIP_OXY_BY_KIND[:cracked_block]
    cracked_block_spawns.each do |spawn|
      exists = stage.any? do |sp|
        chip_kind(sp) == :cracked_block && sp.x == spawn[:x] && sp.y == spawn[:y]
      end
      next if exists

      sp = project.chips.at(ox, oy, spawn[:w], spawn[:h]).to_sprite
      sp.x = spawn[:x]
      sp.y = spawn[:y]
      sp.z = spawn[:z]
      stage << sp
      add_sprite(sp)
    end
  end

  def chip_kind(sprite)
    CHIP_POS[sprite.oy.to_i / 8]&.[](sprite.ox.to_i / 8)
  end

  def set_chip_kind(sprite, kind)
    ox, oy = CHIP_OXY_BY_KIND[kind]
    return unless ox && oy

    sprite.ox = ox
    sprite.oy = oy
  end

  def jump_from_block_top?(sp, other)
    return false unless sp.bottom <= other.top + 1

    @jump_locked = false
    sp.vel = Vector.new(0, -150)
    true
  end

  # プレイヤースプライト
  def player()
    # スプライトエディターの画像から位置と大きさを指定してスプライトを生成
    # 初回呼び出し時のみプレイヤースプライトを生成して保持する
    # 次回呼び出しからは保持している生成済みのインスタンスを返す
    @player ||= project.chips.at(0, 0, 8, 8).to_sprite.tap do |sp|
      # インスタンス生成する初回のみ初期化処理を実行
      # スプライトの初期位置をチェックポイントに合わせる
      sp.x, sp.y = @checkpoint.values_at(:x, :y)
      # 物理演算で動けるスプライトにする
      sp.dynamic = true
      # スプライトが他のスプライトと衝突した際に呼ばれる
      sp.contact do |other|
        # 衝突した相手を、スプライト画像の位置をもとに判別
        case chip_kind(other)
        when :coin # 相手がコインなら
          # コインを配列から消す
          stage.delete(other)
          # コインスプライトを物理エンジンからも削除する
          remove_sprite(other)
          # 1番目のサウンドを再生する
          project.sounds[1].play
        when :spike # 相手がトゲなら
          # トゲ接触は落下と同じ扱いでチェックポイント復帰
          restart_from_fall
          # 2番目のサウンドを再生する
          project.sounds[2].play
        when :goal # ゴール
          clear
        when :block, :active_checkpoint_block, :moving_block, :moving_block_edge # ブロック
          # ブロックの上に着地したときだけジャンプを許可する
          jump_from_block_top?(sp, other)
        when :checkpoint_block # チェックポイントブロック
          # ブロックの上に着地したときだけチェックポイントを更新する
          if jump_from_block_top?(sp, other)
            set_chip_kind(other, :active_checkpoint_block)
            @checkpoint = { x: other.x, y: other.y - 10 }
            project.sounds[1].play
          end
        when :cracked_block # ひび割れブロック
          # ブロックの上に着地したときだけブロックを壊す
          if jump_from_block_top?(sp, other)
            stage.delete(other)
            remove_sprite(other)
            project.sounds[2].play
          end
        end

      end
      # アニメーションのフレーム用カウンター変数
      count = 0
      # 0.5秒ごとに繰り返す
      set_interval(0.5) do
        # スプライトの画像の参照位置（ox は offset x の略）を
        # 交互に 0 と 8 になるようにしてアニメーションさせる
        sp.ox = (count ^= 1) * 8
      end
    end
  end

  def moving_blocks()
    @moving_block_edges ||= stage.select {|sp| chip_kind(sp) == :moving_block_edge}
    @moving_blocks ||= stage.select {|sp| chip_kind(sp) == :moving_block}.tap do |blocks|
      blocks.each do |sp|
        sp[:moving_dir] = 1
        sp[:moving_speed] = MOVING_BLOCK_SPEED
        sp[:moving_base_y] = sp.y
        edges = @moving_block_edges.select {|edge| edge.y == sp.y}.sort_by(&:x)
        left  = edges.select {|edge| edge.x <= sp.x}.last
        right = edges.find {|edge| edge.x >= sp.x}
        if left && right && left != right
          sp[:moving_enabled] = true
          sp[:moving_min_x] = left.right
          sp[:moving_max_x] = right.x - sp.w
        else
          sp[:moving_enabled] = false
        end
      end
    end

    @moving_blocks.each do |sp|
      sp.y = sp[:moving_base_y]
      next unless @state == :playing
      next unless sp[:moving_enabled]

      next_x = sp.x + sp[:moving_dir] * sp[:moving_speed]
      if next_x < sp[:moving_min_x]
        sp.x = sp[:moving_min_x]
        sp[:moving_dir] = 1
      elsif next_x > sp[:moving_max_x]
        sp.x = sp[:moving_max_x]
        sp[:moving_dir] = -1
      else
        sp.x = next_x
      end
    end
  end
end

# 起動時に一度だけ呼ばれる
setup do
  # ゲーム実装のインスタンスを生成
  $game = Game.new
end

# 毎秒60回呼ばれる
draw do
  # ゲームの状態を更新
  $game&.update
  # ゲームを描画
  $game&.draw
end

# キーが押されたら呼ばれる
key_pressed do
  # 押されたキーのキーコード
  key = key_code
  # キーが押されたメソッドを呼ぶ（キーリピートは無視）
  $game&.key_down key unless key_is_repeated
end
