# -*- coding: utf-8 -*-

# ゲームを実装したクラス
class Game
  def initialize()
    @current_oy = 0
    # ジャンプをロックするフラグ
    @jump_locked = false
    # 画面を揺らす量
    @shake = 0
    # ゲーム進行状態
    @state = :ready

    size width / 2, height / 2

    set_timeout do
      # 全スプライトを追加して物理演算処理用に登録しておく
      [*stage, player].each do
        add_sprite(_1)
      end
    end

    # 重力を (x, y) で設定
    gravity(0, 500)
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
  end

  # 描画前にゲームの状態を更新する
  def update()
    return unless @state == :playing

    # 左右カーソルキーでプレイヤースプライトのx軸方向の速度を更新
    player.vx -= 10 if player.vx > -50 && key_is_down(LEFT)
    player.vx += 10 if player.vx < +50 && key_is_down(RIGHT)

    # プレイヤースプライトの速度を減衰させる
    player.vx *= 0.9

    # 画面を揺らす量を減衰させる
    @shake *= 0.8

    # 画面を揺らす量が十分に小さな値になったらゼロにしておく
    @shake = 0 if @shake < 0.1

    # カメラの表示範囲より下に落ちたらゲームオーバー
    @gameover = true if player.bottom > (@current_oy + height)
  end

  def draw_state()
    state_text =
      case @state
      when :ready      then "Press Space"
      when :count_down then @count_down_text
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

    # ゲームオーバーなら表示する
    if @gameover
      # 塗りつぶしの色を赤に
      fill(255, 0, 0)
      # 文字サイズ
      text_size(16)
      # text(str, x, y, w, h) の x, y, w, h の中心にテキストを表示する
      text_align(CENTER, CENTER)
      # Game Over! の文字を画面の中心に描画する
      text("Game Over!", 0, 0, width, height)
    end

    draw_state
  end

  def key_down(key)
    case @state
    when :ready
      return unless key == SPACE
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

  # プレイヤースプライト
  def player()
    # スプライトエディターの画像から位置と大きさを指定してスプライトを生成
    # 初回呼び出し時のみプレイヤースプライトを生成して保持する
    # 次回呼び出しからは保持している生成済みのインスタンスを返す
    @player ||= project.chips.at(0, 0, 8, 8).to_sprite.tap do |sp|
      # インスタンス生成する初回のみ初期化処理を実行
      # スプライトの初期位置を指定
      sp.x, sp.y = 100, 50
      # 物理演算で動けるスプライトにする
      sp.dynamic = true
      # スプライトが他のスプライトと衝突した際に呼ばれる
      sp.contact do |other|
        # 衝突した相手を、スプライト画像の位置をもとに判別
        case [other.ox, other.oy] # ox, oy は offsetx, offsety
        when [8, 32] # 相手がコインなら
          # コインを配列から消す
          stage.delete(other)
          # コインスプライトを物理エンジンからも削除する
          remove_sprite(other)
          # 1番目のサウンドを再生する
          project.sounds[1].play
        when [0, 32] # 相手がトゲなら
          # トゲからプレイヤー向きの単位ベクトルを作る
          dir       = (sp.pos - other.pos).normalize
          # 弾かれるようにプライヤーの速度ベクトルを更新
          sp.vel    = dir * 200
          # 画面を揺らす
          @shake    = 5
          # ゲームオーバーフラグを立てる
          @gameover = true
          # 2番目のサウンドを再生する
          project.sounds[2].play
        when [0, 16] # ブロック
          if sp.bottom <= other.top + 1 # ブロックの上に着地したときだけジャンプを許可する
            @jump_locked = false
            sp.vel = Vector.new(0, -150)
          end
        end

      end
      # アニメーションのフレーム用カウンター変数
      count = 0
      # 0.5秒ごとに繰り返す
      set_interval(0.5) do
        # スプライトの画像の参照位置（ox は offset x の略）を
        # 交互に 0 と 24 になるようにしてアニメーションさせる
        sp.ox = (count += 1) % 2 == 0 ? 0 : 24
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
