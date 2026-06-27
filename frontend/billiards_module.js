"use strict";

// ════════════════════════════════════════════════════════════════
//  🎱 Бильярд — локальная игра на одном экране + онлайн по коду
//  Физика адаптирована из github.com/henshmi/Classic-Pool-Game (MIT)
// ════════════════════════════════════════════════════════════════

// ─── Геометрия ──────────────────────────────────────────────────
function BilVec(x, y) { this.x = x || 0; this.y = y || 0; }
BilVec.prototype.copy = function () { return new BilVec(this.x, this.y); };
BilVec.prototype.add  = function (v) { return new BilVec(this.x + v.x, this.y + v.y); };
BilVec.prototype.mul  = function (s) { return new BilVec(this.x * s, this.y * s); };
BilVec.prototype.dist = function (v) { return Math.hypot(this.x - v.x, this.y - v.y); };

// Размеры стола взяты из оригинала без изменений — физика уже сбалансирована
// под эти пропорции (скорость удара/трение/отскок от бортов настроены под них).
const BIL_W = 1500, BIL_H = 825;
const BIL_BALL_SIZE = 38;
const BIL_BALL_R = 19;
const BIL_BORDER = 57;
const BIL_HOLE_R = 46;
const BIL_DELTA = 1 / 100;
const BIL_MAX_POWER = 75;
const BIL_POWER_SCALE = 0.12; // драг в пикселях канваса -> power

const BIL_LEFT = BIL_BORDER, BIL_RIGHT = BIL_W - BIL_BORDER;
const BIL_TOP = BIL_BORDER, BIL_BOTTOM = BIL_H - BIL_BORDER;

const BIL_HOLES = [
  { pos: new BilVec(750, 32),   r: BIL_HOLE_R + 6 },
  { pos: new BilVec(750, 794),  r: BIL_HOLE_R + 6 },
  { pos: new BilVec(62, 62),    r: BIL_HOLE_R },
  { pos: new BilVec(1435, 62),  r: BIL_HOLE_R },
  { pos: new BilVec(62, 762),   r: BIL_HOLE_R },
  { pos: new BilVec(1435, 762), r: BIL_HOLE_R },
];

const BIL_COLOR_HEX = { white: "#ece7da", red: "#c94c4c", yellow: "#c9a84c", black: "#191920" };
const BIL_COLOR_LABEL = { red: "красные", yellow: "жёлтые" };

function bilIsInsideHole(pos) {
  for (var i = 0; i < BIL_HOLES.length; i++) {
    if (BIL_HOLES[i].pos.dist(pos) < BIL_HOLES[i].r) return true;
  }
  return false;
}
function bilIsOutsideBorder(pos) {
  return pos.x - BIL_BALL_R < BIL_LEFT || pos.x + BIL_BALL_R > BIL_RIGHT ||
         pos.y - BIL_BALL_R < BIL_TOP  || pos.y + BIL_BALL_R > BIL_BOTTOM;
}

// ─── Шар ────────────────────────────────────────────────────────
function BilBall(initPos, color) {
  this.initPos  = initPos;
  this.position = initPos.copy();
  this.velocity = new BilVec(0, 0);
  this.color    = color; // 'white' | 'red' | 'yellow' | 'black'
  this.moving   = false;
  this.visible  = true;
  this.inHole   = false;
}

BilBall.prototype.shoot = function (power, angle) {
  if (power <= 0) return;
  this.moving = true;
  this.velocity = new BilVec(100 * Math.cos(angle) * power, 100 * Math.sin(angle) * power);
};

BilBall.prototype.update = function (delta, onPocket) {
  this.updatePosition(delta, onPocket);
  this.velocity = this.velocity.mul(0.98);
  if (this.moving && Math.abs(this.velocity.x) < 1 && Math.abs(this.velocity.y) < 1) this.stop();
};

BilBall.prototype.updatePosition = function (delta, onPocket) {
  if (!this.moving || this.inHole) return;
  var newPos = this.position.add(this.velocity.mul(delta));

  if (bilIsInsideHole(newPos)) {
    this.position = newPos;
    this.inHole = true;
    var self = this;
    setTimeout(function () { self.visible = false; self.velocity = new BilVec(0, 0); }, 100);
    onPocket(this);
    return;
  }

  var collided = this.handleBorderCollision(newPos);
  if (collided) this.velocity = this.velocity.mul(0.95);
  else this.position = newPos;
};

BilBall.prototype.handleBorderCollision = function (newPos) {
  var collided = false;
  if (newPos.x - BIL_BALL_R < BIL_LEFT) {
    this.velocity.x = -this.velocity.x; this.position.x = BIL_LEFT + BIL_BALL_R; collided = true;
  } else if (newPos.x + BIL_BALL_R > BIL_RIGHT) {
    this.velocity.x = -this.velocity.x; this.position.x = BIL_RIGHT - BIL_BALL_R; collided = true;
  }
  if (newPos.y - BIL_BALL_R < BIL_TOP) {
    this.velocity.y = -this.velocity.y; this.position.y = BIL_TOP + BIL_BALL_R; collided = true;
  } else if (newPos.y + BIL_BALL_R > BIL_BOTTOM) {
    this.velocity.y = -this.velocity.y; this.position.y = BIL_BOTTOM - BIL_BALL_R; collided = true;
  }
  return collided;
};

BilBall.prototype.stop = function () { this.moving = false; this.velocity = new BilVec(0, 0); };
BilBall.prototype.reset = function () {
  this.inHole = false; this.moving = false; this.velocity = new BilVec(0, 0);
  this.position = this.initPos.copy(); this.visible = true;
};
BilBall.prototype.out = function () { this.position = new BilVec(0, BIL_H + 100); this.visible = false; this.inHole = true; };

// ─── Игрок (счёт + назначенный цвет) ───────────────────────────
function BilPlayer() { this.color = null; this.score = 0; }

// ─── Правила игры (фолы, лунки, победа) ────────────────────────
function BilPolicy() {
  this.turn = 0;
  this.firstCollision = true;
  this.foul = false;
  this.scored = false;
  this.won = false;
  this.turnPlayed = false;
  this.players = [new BilPlayer(), new BilPlayer()];
}

BilPolicy.prototype.checkCollisionValidity = function (ball1, ball2) {
  var currentColor = this.players[this.turn].color;

  if (this.players[this.turn].score === 7 && (ball1.color === "black" || ball2.color === "black")) {
    this.firstCollision = false;
    return;
  }
  if (!this.firstCollision) return;
  if (currentColor == null) { this.firstCollision = false; return; }

  if (ball1.color === "white") {
    if (ball2.color !== currentColor) this.foul = true;
    this.firstCollision = false;
  }
  if (ball2.color === "white") {
    if (ball1.color !== currentColor) this.foul = true;
    this.firstCollision = false;
  }
};

BilPolicy.prototype.handleBallInHole = function (ball, table) {
  setTimeout(function () { ball.out(); }, 100);

  var currentPlayer = this.players[this.turn];
  var secondPlayer  = this.players[(this.turn + 1) % 2];

  if (currentPlayer.color == null) {
    if (ball.color === "red")    { currentPlayer.color = "red";    secondPlayer.color = "yellow"; }
    else if (ball.color === "yellow") { currentPlayer.color = "yellow"; secondPlayer.color = "red"; }
    else if (ball.color === "black") { this.won = true; this.foul = true; }
    else if (ball.color === "white") { this.foul = true; }
  }

  if (currentPlayer.color === ball.color) {
    currentPlayer.score++;
    this.scored = true;
  } else if (ball.color === "white") {
    if (currentPlayer.color != null) {
      this.foul = true;
      var setBalls = table.getBallsByColor(currentPlayer.color);
      var allIn = setBalls.every(function (b) { return b.inHole; });
      if (allIn) this.won = true;
    }
  } else if (ball.color === "black") {
    if (currentPlayer.color != null) {
      var ownBalls = table.getBallsByColor(currentPlayer.color);
      if (!ownBalls.every(function (b) { return b.inHole; })) this.foul = true;
      this.won = true;
    }
  } else {
    secondPlayer.score++;
    this.foul = true;
  }
};

BilPolicy.prototype.switchTurns = function () { this.turn = (this.turn + 1) % 2; };

// Возвращает true, если партия только что завершилась (есть победитель).
BilPolicy.prototype.updateTurnOutcome = function () {
  if (!this.turnPlayed) return false;

  if (this.firstCollision) this.foul = true;

  if (this.won) {
    if (!this.foul) this.winnerIdx = this.turn;
    else this.winnerIdx = (this.turn + 1) % 2;
    return true;
  }

  if (!this.scored || this.foul) this.switchTurns();

  this.scored = false;
  this.turnPlayed = false;
  this.firstCollision = true;
  return false;
};

BilPolicy.prototype.serialize = function () {
  return {
    turn: this.turn, firstCollision: this.firstCollision, foul: this.foul,
    scored: this.scored, won: this.won, turnPlayed: this.turnPlayed,
    players: this.players.map(function (p) { return { color: p.color, score: p.score }; }),
  };
};
BilPolicy.prototype.load = function (s) {
  this.turn = s.turn; this.firstCollision = s.firstCollision; this.foul = s.foul;
  this.scored = s.scored; this.won = s.won; this.turnPlayed = s.turnPlayed;
  this.players[0].color = s.players[0].color; this.players[0].score = s.players[0].score;
  this.players[1].color = s.players[1].color; this.players[1].score = s.players[1].score;
};

// ─── Стол (расстановка шаров + столкновения) ───────────────────
// Координаты треугольника взяты из оригинала — уже без перекрытий под BIL_BALL_SIZE.
function BilTable() {
  this.whiteBall = new BilBall(new BilVec(413, 413), "white");
  this.blackBall = new BilBall(new BilVec(1090, 413), "black");
  this.redBalls = [
    new BilBall(new BilVec(1056, 433), "red"), new BilBall(new BilVec(1090, 374), "red"),
    new BilBall(new BilVec(1126, 393), "red"), new BilBall(new BilVec(1126, 472), "red"),
    new BilBall(new BilVec(1162, 335), "red"), new BilBall(new BilVec(1162, 374), "red"),
    new BilBall(new BilVec(1162, 452), "red"),
  ];
  this.yellowBalls = [
    new BilBall(new BilVec(1022, 413), "yellow"), new BilBall(new BilVec(1056, 393), "yellow"),
    new BilBall(new BilVec(1090, 452), "yellow"), new BilBall(new BilVec(1126, 354), "yellow"),
    new BilBall(new BilVec(1126, 433), "yellow"), new BilBall(new BilVec(1162, 413), "yellow"),
    new BilBall(new BilVec(1162, 491), "yellow"),
  ];
  this.balls = [
    this.yellowBalls[0], this.yellowBalls[1], this.redBalls[0], this.redBalls[1], this.blackBall,
    this.yellowBalls[2], this.yellowBalls[3], this.redBalls[2], this.yellowBalls[4], this.redBalls[3],
    this.redBalls[4], this.redBalls[5], this.yellowBalls[5], this.redBalls[6], this.yellowBalls[6],
    this.whiteBall,
  ];
}

BilTable.prototype.getBallsByColor = function (color) {
  if (color === "red") return this.redBalls;
  if (color === "yellow") return this.yellowBalls;
  return [];
};

BilTable.prototype.ballsMoving = function () { return this.balls.some(function (b) { return b.moving; }); };

BilTable.prototype.whiteBallOverlapsOthers = function (pos) {
  var white = this.whiteBall;
  return this.balls.some(function (b) {
    return b !== white && b.visible && !b.inHole && pos.dist(b.position) < BIL_BALL_SIZE;
  });
};

BilTable.prototype.handlePairCollision = function (ball1, ball2, delta, policy) {
  if (ball1.inHole || ball2.inHole) return;
  if (!ball1.moving && !ball2.moving) return;

  var p1 = ball1.position.add(ball1.velocity.mul(delta));
  var p2 = ball2.position.add(ball2.velocity.mul(delta));
  if (p1.dist(p2) >= BIL_BALL_SIZE) return;

  policy.checkCollisionValidity(ball1, ball2);

  var power = (Math.abs(ball1.velocity.x) + Math.abs(ball1.velocity.y)) +
              (Math.abs(ball2.velocity.x) + Math.abs(ball2.velocity.y));
  power *= 0.00482;

  var opposite = ball1.position.y - ball2.position.y;
  var adjacent = ball1.position.x - ball2.position.x;
  var rotation = Math.atan2(opposite, adjacent);

  ball1.moving = true; ball2.moving = true;

  var v2 = new BilVec(90 * Math.cos(rotation + Math.PI) * power, 90 * Math.sin(rotation + Math.PI) * power);
  ball2.velocity = ball2.velocity.add(v2).mul(0.97);

  var v1 = new BilVec(90 * Math.cos(rotation) * power, 90 * Math.sin(rotation) * power);
  ball1.velocity = ball1.velocity.add(v1).mul(0.97);
};

BilTable.prototype.update = function (delta, policy) {
  for (var i = 0; i < this.balls.length; i++) {
    for (var j = i + 1; j < this.balls.length; j++) {
      this.handlePairCollision(this.balls[i], this.balls[j], delta, policy);
    }
  }
  var self = this;
  for (var k = 0; k < this.balls.length; k++) {
    this.balls[k].update(delta, function (ball) { policy.handleBallInHole(ball, self); });
  }
};

BilTable.prototype.serialize = function () {
  return this.balls.map(function (b) {
    return { x: b.position.x, y: b.position.y, visible: b.visible, inHole: b.inHole };
  });
};
BilTable.prototype.load = function (arr) {
  for (var i = 0; i < this.balls.length && i < arr.length; i++) {
    this.balls[i].position = new BilVec(arr[i].x, arr[i].y);
    this.balls[i].visible = arr[i].visible;
    this.balls[i].inHole = arr[i].inHole;
    this.balls[i].moving = false;
    this.balls[i].velocity = new BilVec(0, 0);
  }
};

// ─── Кий (прицеливание + удар) ──────────────────────────────────
function BilStick() { this.rotation = 0; this.power = 0; this.aiming = false; }

// ─── Контроллер игры: рендер, ввод (мышь+тач), сеть ─────────────
function BilGame(canvas) {
  this.canvas = canvas;
  this.ctx = canvas.getContext("2d");
  this.table = new BilTable();
  this.policy = new BilPolicy();
  this.stick = new BilStick();
  this.isLocal = true;
  this.myPlayerIndex = 0; // в онлайне: 0 = player1, 1 = player2
  this.placingWhiteBall = false;
  this.pendingPos = null;
  this.dragPos = null;
  this.running = false;
  this.onTurnSettled = null;   // (winnerIdx|null) => void
  this.onChange = null;        // вызывается при любом визуальном изменении (для обновления чипов)
  this.onPowerChange = null;   // (power|null) => void — null значит "спрятать индикатор силы"
  this._bindInput();
}

BilGame.prototype.reset = function () {
  this.table = new BilTable();
  this.policy = new BilPolicy();
  this.placingWhiteBall = false;
  this.pendingPos = null;
};

BilGame.prototype.canIInteract = function () {
  if (this.policy.turnPlayed) return false;
  if (this.table.ballsMoving()) return false;
  if (!this.isLocal && this.policy.turn !== this.myPlayerIndex) return false;
  return true;
};

BilGame.prototype._logicalPos = function (clientX, clientY) {
  var rect = this.canvas.getBoundingClientRect();
  return new BilVec(
    (clientX - rect.left) / rect.width * BIL_W,
    (clientY - rect.top) / rect.height * BIL_H
  );
};

BilGame.prototype._bindInput = function () {
  var self = this;
  function posFromEvent(e) {
    if (e.touches && e.touches.length) return self._logicalPos(e.touches[0].clientX, e.touches[0].clientY);
    if (e.changedTouches && e.changedTouches.length) return self._logicalPos(e.changedTouches[0].clientX, e.changedTouches[0].clientY);
    return self._logicalPos(e.clientX, e.clientY);
  }

  function onDown(e) {
    e.preventDefault();
    if (!self.canIInteract()) return;
    var pos = posFromEvent(e);

    if (self.policy.foul) {
      if (!bilIsOutsideBorder(pos) && !bilIsInsideHole(pos) && !self.table.whiteBallOverlapsOthers(pos)) {
        self.table.whiteBall.position = pos;
        self.table.whiteBall.inHole = false;
        self.table.whiteBall.visible = true;
        self.policy.foul = false;
        self.placingWhiteBall = false;
        if (self.onChange) self.onChange();
      }
      self.draw();
      return;
    }

    self.dragPos = pos;
    self.stick.aiming = true;
    self.draw();
  }

  function onMove(e) {
    if (self.policy.foul && self.canIInteract()) {
      var p = posFromEvent(e);
      if (!bilIsOutsideBorder(p) && !self.table.whiteBallOverlapsOthers(p)) {
        self.table.whiteBall.position = p;
      }
      self.draw();
      return;
    }
    if (!self.stick.aiming) return;
    e.preventDefault();
    self.dragPos = posFromEvent(e);
    var white = self.table.whiteBall.position;
    var dx = white.x - self.dragPos.x, dy = white.y - self.dragPos.y;
    var dist = Math.hypot(dx, dy);
    self.stick.rotation = Math.atan2(dy, dx);
    self.stick.power = Math.min(BIL_MAX_POWER, dist * BIL_POWER_SCALE);
    if (self.onPowerChange) self.onPowerChange(self.stick.power);
    self.draw();
  }

  function onUp(e) {
    if (!self.stick.aiming) return;
    self.stick.aiming = false;
    if (self.onPowerChange) self.onPowerChange(null);
    if (self.stick.power > 3) {
      self.shoot(self.stick.power, self.stick.rotation);
    } else {
      self.draw();
    }
    self.stick.power = 0;
  }

  this.canvas.addEventListener("mousedown", onDown);
  this.canvas.addEventListener("mousemove", onMove);
  window.addEventListener("mouseup", onUp);
  this.canvas.addEventListener("touchstart", onDown, { passive: false });
  this.canvas.addEventListener("touchmove", onMove, { passive: false });
  window.addEventListener("touchend", onUp);
};

// power+rotation — общий путь и для локального удара, и для воспроизведения удара соперника
BilGame.prototype.shoot = function (power, rotation, fromNetwork) {
  this.policy.turnPlayed = true;
  this.table.whiteBall.shoot(power, rotation);
  if (!fromNetwork && this.onShot) this.onShot(power, rotation);
  if (!this.running) this.startLoop();
};

BilGame.prototype.startLoop = function () {
  if (this.running) return;
  this.running = true;
  var self = this;
  function tick() {
    if (!self.running) return;
    self.table.update(BIL_DELTA, self.policy);
    if (!self.table.ballsMoving() && self.policy.turnPlayed) {
      var finished = self.policy.updateTurnOutcome();
      if (self.policy.foul && !finished) self.placingWhiteBall = true;
      if (self.onTurnSettled) self.onTurnSettled(finished ? self.policy.winnerIdx : null);
      self.running = false;
      self.draw();
      if (self.onChange) self.onChange();
      return;
    }
    self.draw();
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
};

BilGame.prototype.serialize = function () {
  return { balls: this.table.serialize(), policy: this.policy.serialize() };
};
BilGame.prototype.load = function (state) {
  if (!state) return;
  this.table.load(state.balls);
  this.policy.load(state.policy);
};

// ─── Рендер ──────────────────────────────────────────────────────
BilGame.prototype.draw = function () {
  var ctx = this.ctx;
  ctx.clearRect(0, 0, BIL_W, BIL_H);

  // Рейка (борт)
  ctx.fillStyle = "#4a3214";
  ctx.fillRect(0, 0, BIL_W, BIL_H);
  // Сукно
  ctx.fillStyle = "#0f3d2b";
  ctx.fillRect(BIL_BORDER, BIL_BORDER, BIL_W - 2 * BIL_BORDER, BIL_H - 2 * BIL_BORDER);

  // Лунки
  ctx.fillStyle = "#0a0a0f";
  BIL_HOLES.forEach(function (h) {
    ctx.beginPath(); ctx.arc(h.pos.x, h.pos.y, h.r, 0, Math.PI * 2); ctx.fill();
  });

  // Шары
  this.table.balls.forEach(function (b) {
    if (!b.visible) return;
    ctx.beginPath();
    ctx.arc(b.position.x, b.position.y, BIL_BALL_R, 0, Math.PI * 2);
    ctx.fillStyle = BIL_COLOR_HEX[b.color] || "#fff";
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = b.color === "white" ? "rgba(0,0,0,0.25)" : "rgba(0,0,0,0.35)";
    ctx.stroke();
    // блик
    ctx.beginPath();
    ctx.arc(b.position.x - BIL_BALL_R * 0.35, b.position.y - BIL_BALL_R * 0.35, BIL_BALL_R * 0.3, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(255,255,255,0.35)";
    ctx.fill();
  });

  // Кий + направляющая, только когда можно бить
  if (this.canIInteract() && !this.policy.foul && this.stick.aiming) {
    var white = this.table.whiteBall.position;
    var dx = Math.cos(this.stick.rotation), dy = Math.sin(this.stick.rotation);
    var frac = this.stick.power / BIL_MAX_POWER; // 0..1
    var tint = frac > 0.75 ? "#c96442" : frac > 0.4 ? "#c89826" : "#8aa46b";

    // Линия прицеливания — куда полетит шар. Длина и яркость растут с силой удара.
    var aimLen = 130 + frac * 380;
    ctx.save();
    ctx.setLineDash([12, 10]);
    ctx.strokeStyle = tint;
    ctx.globalAlpha = 0.45 + frac * 0.4;
    ctx.lineWidth = 2 + frac * 2;
    ctx.beginPath();
    ctx.moveTo(white.x, white.y);
    ctx.lineTo(white.x - dx * aimLen, white.y - dy * aimLen);
    ctx.stroke();
    ctx.restore();

    // Точка прогноза — где окажется шар при ударе текущей силы
    ctx.beginPath();
    ctx.arc(white.x - dx * aimLen, white.y - dy * aimLen, 6, 0, Math.PI * 2);
    ctx.fillStyle = tint;
    ctx.fill();

    // Сам кий, оттянутый назад пропорционально силе удара
    var pullBack = BIL_BALL_R + 6 + frac * 170;
    ctx.strokeStyle = "#c9a84c";
    ctx.lineWidth = 6;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(white.x + dx * pullBack, white.y + dy * pullBack);
    ctx.lineTo(white.x + dx * (pullBack + 140), white.y + dy * (pullBack + 140));
    ctx.stroke();
  }
};

// ════════════════════════════════════════════════════════════════
//  Экраны / лобби / онлайн-обвязка
// ════════════════════════════════════════════════════════════════

var _bil = {
  game: null, ws: null, code: null, myUserId: null, isLocal: false,
  _waitPoll: null, _gamePoller: null, _lastWsMsgTime: 0,
};

function _bilWsBase() {
  var base = (typeof API_BASE_URL !== "undefined" ? API_BASE_URL : "") || "";
  if (base.startsWith("http")) return base.replace(/^http/, "ws");
  var l = window.location;
  return (l.protocol === "https:" ? "wss" : "ws") + "://" + l.host;
}

function _showBilliardsScreen(id) {
  ["games-lobby", "billiards-entry", "billiards-waiting", "billiards-game"].forEach(function (s) {
    var el = $(s); if (el) el.style.display = s === id ? "" : "none";
  });
}

function initBilliardsMode() {
  _showBilliardsScreen("billiards-entry");
  var backBtn = $("billiards-back-to-lobby");
  if (backBtn && !backBtn._init) { backBtn._init = true; backBtn.addEventListener("click", function () { _showBilliardsScreen("games-lobby"); }); }
  var createBtn = $("billiards-create-btn");
  if (createBtn && !createBtn._init) { createBtn._init = true; createBtn.addEventListener("click", billiardsCreateGame); }
  var joinBtn = $("billiards-join-btn");
  if (joinBtn && !joinBtn._init) { joinBtn._init = true; joinBtn.addEventListener("click", billiardsJoinGame); }
  var joinInput = $("billiards-join-input");
  if (joinInput && !joinInput._init) {
    joinInput._init = true;
    joinInput.addEventListener("keydown", function (e) { if (e.key === "Enter") billiardsJoinGame(); });
    joinInput.addEventListener("input", function () { joinInput.value = joinInput.value.toUpperCase(); });
  }
  var localBtn = $("billiards-local-btn");
  if (localBtn && !localBtn._init) { localBtn._init = true; localBtn.addEventListener("click", billiardsStartLocal); }
}

function _bilSetupGame() {
  var canvas = $("billiards-canvas");
  if (_bil.game) return _bil.game;
  var g = new BilGame(canvas);
  g.onChange = _bilRenderChips;
  g.onPowerChange = _bilRenderPower;
  g.onShot = function (power, rotation) {
    _bilLastShooterIdx = g.policy.turn;
    if (!_bil.isLocal && _bil.ws && _bil.ws.readyState === WebSocket.OPEN) {
      _bil.ws.send(JSON.stringify({ type: "shot", power: power, rotation: rotation }));
    }
  };
  g.onTurnSettled = function (winnerIdx) {
    _bilRenderChips();
    if (winnerIdx != null) {
      _bilShowGameOver(winnerIdx);
    }
    if (!_bil.isLocal && _bilAmShooterThisSettle()) {
      _bilSendStateSync(winnerIdx);
    }
  };
  _bil.game = g;
  return g;
}

// После updateTurnOutcome turn уже переключился на оппонента (если не фол/скор) —
// поэтому "кто только что стрелял" надёжнее всего помнить явным флагом на каждый выстрел.
var _bilLastShooterIdx = null;
function _bilAmShooterThisSettle() {
  return _bilLastShooterIdx === _bil.game.myPlayerIndex;
}

function _bilSendStateSync(winnerIdx) {
  if (!_bil.ws || _bil.ws.readyState !== WebSocket.OPEN) return;
  var payload = { type: "state", state: _bil.game.serialize() };
  if (winnerIdx != null) {
    payload.status = "finished";
    payload.winner = winnerIdx === 0 ? _bil.game._player1Id : _bil.game._player2Id;
  }
  _bil.ws.send(JSON.stringify(payload));
}

function _bilRenderPower(power) {
  var wrap = $("billiards-power-wrap");
  var fill = $("billiards-power-fill");
  var pct = $("billiards-power-pct");
  if (!wrap || !fill || !pct) return;
  if (power == null) { wrap.style.visibility = "hidden"; fill.style.width = "0%"; return; }
  wrap.style.visibility = "visible";
  var frac = Math.min(1, power / BIL_MAX_POWER);
  fill.style.width = Math.round(frac * 100) + "%";
  fill.classList.toggle("tier-mid", frac > 0.4 && frac <= 0.75);
  fill.classList.toggle("tier-high", frac > 0.75);
  pct.textContent = Math.round(frac * 100) + "%";
}

function _bilRenderChips() {
  var g = _bil.game; if (!g) return;
  [0, 1].forEach(function (i) {
    var p = g.policy.players[i];
    var nameEl = $("billiards-p" + (i + 1) + "-name");
    var colorEl = $("billiards-p" + (i + 1) + "-color");
    var scoreEl = $("billiards-p" + (i + 1) + "-score");
    var chipEl = $("billiards-p" + (i + 1) + "-chip");
    if (colorEl) colorEl.textContent = p.color ? BIL_COLOR_LABEL[p.color] : "";
    if (scoreEl) scoreEl.textContent = String(p.score);
    if (chipEl) chipEl.classList.toggle("billiards-turn-active", g.policy.turn === i);
  });
  var hint = $("billiards-hint");
  if (hint) {
    if (g.policy.foul) hint.textContent = "Фол! Поставь белый шар куда хочешь и продолжай.";
    else hint.textContent = "";
  }
  var label = $("billiards-turn-label");
  if (label) {
    var canShoot = g.isLocal || g.policy.turn === g.myPlayerIndex;
    label.textContent = canShoot ? "Твой удар" : "Ход соперника";
  }
}

function _bilShowGameOver(winnerIdx) {
  var overlay = $("billiards-gameover");
  if (!overlay) return;
  var title = $("billiards-gameover-title");
  var g = _bil.game;
  var iWon = g.isLocal ? true : winnerIdx === g.myPlayerIndex;
  if (title) {
    if (g.isLocal) title.textContent = "Победил игрок " + (winnerIdx + 1) + "!";
    else title.textContent = iWon ? "Ты выиграл! 🎉" : "Ты проиграл";
  }
  overlay.style.display = "";
  var newBtn = $("billiards-gameover-new");
  if (newBtn) newBtn.style.display = g.isLocal ? "" : "none";
}

// ── Локальная игра: один экран, два игрока ──────────────────────
function billiardsStartLocal() {
  _bil.isLocal = true;
  _bil.code = null;
  _showBilliardsScreen("billiards-game");
  var goEl = $("billiards-gameover"); if (goEl) goEl.style.display = "none";
  var resignBtn = $("billiards-resign-btn"); if (resignBtn) resignBtn.style.display = "none";
  var g = _bilSetupGame();
  g.isLocal = true;
  g.reset();
  $("billiards-p1-name").textContent = "Игрок 1";
  $("billiards-p2-name").textContent = "Игрок 2";
  g.draw();
  _bilRenderChips();
  _bilInitGameOverButtons();
}

function _bilInitGameOverButtons() {
  var newBtn = $("billiards-gameover-new");
  if (newBtn && !newBtn._init) {
    newBtn._init = true;
    newBtn.addEventListener("click", function () {
      $("billiards-gameover").style.display = "none";
      billiardsStartLocal();
    });
  }
  var lobbyBtn = $("billiards-gameover-lobby");
  if (lobbyBtn && !lobbyBtn._init) {
    lobbyBtn._init = true;
    lobbyBtn.addEventListener("click", function () {
      $("billiards-gameover").style.display = "none";
      billiardsDisconnect();
      _showBilliardsScreen("games-lobby");
    });
  }
}

// ── Онлайн: создать / войти по коду ──────────────────────────────
async function billiardsCreateGame() {
  var uid = _bil.myUserId;
  if (!uid) { toast("Войдите в аккаунт, чтобы играть онлайн. Для игры вдвоём на одном экране вход не нужен.", "error"); return; }
  try {
    var game = await apiFetch("/billiards/games?user_id=" + uid, { method: "POST" });
    _bil.isLocal = false;
    _bil.code = game.code;
    _showBilliardsScreen("billiards-waiting");
    var codeEl = $("billiards-game-code-display"); if (codeEl) codeEl.textContent = game.code;
    var backBtn = $("billiards-back-from-waiting");
    if (backBtn && !backBtn._init) {
      backBtn._init = true;
      backBtn.addEventListener("click", function () { billiardsDisconnect(); _showBilliardsScreen("billiards-entry"); });
    }
    var copyBtn = $("billiards-copy-code-btn");
    if (copyBtn && !copyBtn._init) {
      copyBtn._init = true;
      copyBtn.addEventListener("click", function () {
        navigator.clipboard.writeText(game.code).then(function () {
          copyBtn.textContent = "✓ Скопировано!";
          setTimeout(function () { copyBtn.textContent = "📋 Скопировать код"; }, 2000);
        });
      });
    }
    _bilConnect(game.code);
    _bil._waitPoll = setInterval(async function () {
      var gameEl = $("billiards-game");
      if (!gameEl || gameEl.style.display !== "none") { clearInterval(_bil._waitPoll); _bil._waitPoll = null; return; }
      try {
        var g = await apiFetch("/billiards/games/" + game.code);
        if (g && g.status === "active") {
          clearInterval(_bil._waitPoll); _bil._waitPoll = null;
          _bilStartGameUI(g);
        }
      } catch (e) {}
    }, 3000);
  } catch (e) {
    toast((e && e.detail) || "Ошибка создания игры", "error");
  }
}

async function billiardsJoinGame() {
  var inp = $("billiards-join-input");
  var code = inp ? inp.value.trim().toUpperCase() : "";
  if (!code || code.length < 4) { toast("Введи код игры", "error"); return; }
  var uid = _bil.myUserId;
  if (!uid) { toast("Войдите в аккаунт, чтобы играть онлайн. Для игры вдвоём на одном экране вход не нужен.", "error"); return; }
  try {
    var game = await apiFetch("/billiards/games/" + code + "/join?user_id=" + uid, { method: "POST" });
    _bil.isLocal = false;
    _bil.code = game.code;
    _bilStartGameUI(game);
    _bilConnect(game.code);
  } catch (e) {
    toast((e && e.detail) || "Игра не найдена или уже началась", "error");
  }
}

function _bilStartGameUI(game) {
  _showBilliardsScreen("billiards-game");
  var goEl = $("billiards-gameover"); if (goEl) goEl.style.display = "none";
  var resignBtn = $("billiards-resign-btn"); if (resignBtn) resignBtn.style.display = "";
  var g = _bilSetupGame();
  g.isLocal = false;
  if (game.state && game.state.balls) g.load(game.state);
  else g.reset();
  var uid = _bil.myUserId;
  g.myPlayerIndex = game.player1_id === uid ? 0 : 1;
  g._player1Id = game.player1_id; g._player2Id = game.player2_id;
  var p1Name = $("billiards-p1-name"); if (p1Name) p1Name.textContent = game.player1_name || "Игрок 1";
  var p2Name = $("billiards-p2-name"); if (p2Name) p2Name.textContent = game.player2_name || "Игрок 2";
  g.draw();
  _bilRenderChips();
  if (resignBtn && !resignBtn._init) {
    resignBtn._init = true;
    resignBtn.addEventListener("click", function () {
      if (!confirm("Сдаться?")) return;
      if (_bil.ws && _bil.ws.readyState === WebSocket.OPEN) _bil.ws.send(JSON.stringify({ type: "resign" }));
    });
  }
  _bilInitGameOverButtons();
  _bilStartPoller();
}

function _bilConnect(code) {
  if (_bil.ws) { try { _bil.ws.close(); } catch (e) {} }
  var uid = _bil.myUserId;
  var ws = new WebSocket(_bilWsBase() + "/billiards/ws/" + code + "?user_id=" + uid);
  _bil.ws = ws;
  _bil._lastWsMsgTime = Date.now();
  ws.onmessage = function (e) {
    _bil._lastWsMsgTime = Date.now();
    try { _bilHandleMessage(JSON.parse(e.data)); } catch (err) { console.error("billiards WS message error:", err); }
  };
  ws.onerror = function () {};
  ws.onclose = function () {
    if (_bil.code && !_bil.isLocal) {
      setTimeout(function () {
        var gameEl = $("billiards-game");
        if (_bil.code && gameEl) _bilConnect(_bil.code);
      }, 3000);
    }
  };
  ws._pingInterval = setInterval(function () {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: "ping" }));
  }, 25000);
}

function _bilHandleMessage(msg) {
  if (msg.type === "game_ready") {
    _bilStartGameUI(msg.game);
  } else if (msg.type === "shot") {
    if (msg.user_id === _bil.myUserId) return; // эхо своего же выстрела
    _bilLastShooterIdx = _bil.game.policy.turn;
    _bil.game.shoot(msg.power, msg.rotation, true);
  } else if (msg.type === "state_sync") {
    if (!msg.game) return;
    if (msg.game.status === "finished") {
      var iWon = msg.game.winner === _bil.myUserId;
      _bilStopPoller();
      var overlay = $("billiards-gameover"); var title = $("billiards-gameover-title");
      if (title) title.textContent = iWon ? "Ты выиграл! 🎉" : "Ты проиграл";
      if (overlay) overlay.style.display = "";
      return;
    }
    // Применяем состояние только если у нас сейчас ничего не движется —
    // не дёргаем шары посреди локальной анимации удара.
    if (_bil.game && msg.game.state && !_bil.game.table.ballsMoving()) {
      _bil.game.load(msg.game.state);
      _bilRenderChips();
      _bil.game.draw();
    }
  } else if (msg.type === "game_over") {
    var won = msg.winner === _bil.myUserId;
    var overlay2 = $("billiards-gameover"); var title2 = $("billiards-gameover-title");
    if (title2) title2.textContent = msg.reason === "resign" ? (won ? "Соперник сдался — ты выиграл! 🎉" : "Ты сдался") : (won ? "Ты выиграл! 🎉" : "Ты проиграл");
    if (overlay2) overlay2.style.display = "";
    _bilStopPoller();
  } else if (msg.type === "opponent_disconnected") {
    var label = $("billiards-turn-label"); if (label) label.textContent = "Соперник отключился…";
  }
}

function _bilStartPoller() {
  _bilStopPoller();
  _bil._gamePoller = setInterval(async function () {
    var gameEl = $("billiards-game");
    if (!gameEl || gameEl.style.display === "none" || !_bil.code || _bil.isLocal) { _bilStopPoller(); return; }
    var wsSilentMs = Date.now() - (_bil._lastWsMsgTime || 0);
    var wsAlive = _bil.ws && _bil.ws.readyState === WebSocket.OPEN && wsSilentMs < 2000;
    if (wsAlive) return;
    try {
      var g = await apiFetch("/billiards/games/" + _bil.code);
      if (!g) return;
      _bilHandleMessage({ type: "state_sync", game: g });
    } catch (e) {}
  }, 1000);
}
function _bilStopPoller() { if (_bil._gamePoller) { clearInterval(_bil._gamePoller); _bil._gamePoller = null; } }

function billiardsDisconnect() {
  if (_bil._waitPoll) { clearInterval(_bil._waitPoll); _bil._waitPoll = null; }
  _bilStopPoller();
  if (_bil.ws) { clearInterval(_bil.ws._pingInterval); try { _bil.ws.close(); } catch (e) {} _bil.ws = null; }
  _bil.code = null;
  _bil.isLocal = false;
  if (_bil.game) _bil.game.running = false;
  ["billiards-resign-btn", "billiards-gameover-new", "billiards-gameover-lobby",
   "billiards-back-from-waiting", "billiards-copy-code-btn"].forEach(function (id) {
    var el = $(id); if (el) el._init = false;
  });
}
