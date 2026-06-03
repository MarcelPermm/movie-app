
// ════════════════════════════════════════════════════════════════
//  🃏 UNO + 101 — общий движок для карточных игр
// ════════════════════════════════════════════════════════════════

// ─── Общие утилиты ───────────────────────────────────────────────

function _cgWsBase() {
  var base = (typeof API_BASE_URL !== 'undefined' ? API_BASE_URL : '') || '';
  if (base.startsWith('http')) return base.replace(/^http/, 'ws');
  var l = window.location;
  return (l.protocol === 'https:' ? 'wss' : 'ws') + '://' + l.host;
}

function _cgShowScreen(screens, id) {
  screens.forEach(function(s) {
    var el = $(s); if (el) el.style.display = s === id ? '' : 'none';
  });
}

function _cgMakeGame(prefix, screens, mgr) {
  var g = {
    prefix: prefix, screens: screens, mgr: mgr,
    ws: null, code: null, state: null, myHand: [],
    myUserId: null, selectedCard: null, game: null,
  };
  return g;
}

function _cgConnect(g, code) {
  if (g.ws) { clearInterval(g.ws._ping); try { g.ws.close(); } catch(e) {} }
  var uid = g.myUserId;
  var ws = new WebSocket(_cgWsBase() + '/' + g.prefix + '/ws/' + code + '?user_id=' + uid);
  g.ws = ws;
  ws.onmessage = function(e) { try { g.onMsg(JSON.parse(e.data)); } catch(err) { console.error(g.prefix, err); } };
  ws.onerror = function() {};
  ws.onclose = function() {
    if (g.code) {
      setTimeout(function() { if (g.code) _cgConnect(g, g.code); }, 3000);
    }
  };
  ws._ping = setInterval(function() {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping' }));
  }, 25000);
}

function _cgSend(g, msg) {
  if (g.ws && g.ws.readyState === WebSocket.OPEN) g.ws.send(JSON.stringify(msg));
}

function _cgDisconnect(g) {
  if (g.ws) { clearInterval(g.ws._ping); try { g.ws.close(); } catch(e) {} g.ws = null; }
  g.code = null; g.state = null; g.myHand = []; g.selectedCard = null; g.game = null;
  ['create-btn','join-btn','copy-btn','start-btn','back-lobby','back-setup',
   'play-btn','draw-btn','uno-btn','draw-one-btn','next-round-btn','go-new','go-lobby'].forEach(function(sfx) {
    var el = $(g.prefix + '-' + sfx); if (el) el._init = false;
  });
  ['players-group'].forEach(function(sfx) {
    var el = $(g.prefix + '-' + sfx); if (el) el._init = false;
  });
}

async function _cgCreateGame(g, body) {
  try {
    var resp = await apiFetch('/' + g.prefix + '/games?user_id=' + g.myUserId, {
      method: 'POST', body: JSON.stringify(body),
    });
    g.code = resp.game.code; g.game = resp.game;
    _cgShowLobby(g, resp.game, resp.players);
    _cgConnect(g, resp.game.code);
  } catch(e) { toast((e && e.detail) || 'Ошибка создания игры', 'error'); }
}

async function _cgJoinGame(g, inputId) {
  var inp = $(g.prefix + '-join-input');
  var code = inp ? inp.value.trim().toUpperCase() : '';
  if (code.length < 4) { toast('Введи код', 'error'); return; }
  try {
    var resp = await apiFetch('/' + g.prefix + '/games/' + code + '/join?user_id=' + g.myUserId, { method: 'POST' });
    g.code = code; g.game = resp.game;
    if (resp.game.status === 'active') { _cgConnect(g, code); }
    else { _cgShowLobby(g, resp.game, resp.players); _cgConnect(g, code); }
  } catch(e) { toast((e && e.detail) || 'Игра не найдена', 'error'); }
}

function _cgShowLobby(g, game, players) {
  _cgShowScreen(g.screens, g.prefix + '-lobby');
  var codeEl = $(g.prefix + '-code-display'); if (codeEl) codeEl.textContent = game.code;
  _cgUpdateLobbyPlayers(g, players, game);
  _cgInitLobbyBtns(g, game);
}

function _cgUpdateLobbyPlayers(g, players, game) {
  var list = $(g.prefix + '-players-list'); if (!list) return;
  var max = game.max_players;
  list.innerHTML = Array.from({length: max}, function(_, i) {
    var p = players[i];
    return '<div class="durak-lobby-player ' + (p ? 'filled' : 'empty') + '">'
      + (p ? ('👤 ' + p.display_name) : '⋯ ожидание') + '</div>';
  }).join('');
  var full = players.length >= max;
  var dots = $(g.prefix + '-waiting-dots'); if (dots) dots.style.display = full ? 'none' : '';
  var startBtn = $(g.prefix + '-start-btn');
  if (startBtn) startBtn.style.display = (!full && game.created_by === g.myUserId && players.length >= 2) ? '' : 'none';
}

function _cgInitLobbyBtns(g, game) {
  var backBtn = $(g.prefix + '-back-setup');
  if (backBtn && !backBtn._init) {
    backBtn._init = true;
    backBtn.addEventListener('click', function() { _cgDisconnect(g); _cgShowScreen(g.screens, g.prefix + '-setup'); g.initSetup(); });
  }
  var copyBtn = $(g.prefix + '-copy-btn');
  if (copyBtn && !copyBtn._init) {
    copyBtn._init = true;
    copyBtn.addEventListener('click', function() {
      navigator.clipboard.writeText(game.code).then(function() {
        copyBtn.textContent = '✓ Скопировано!';
        setTimeout(function() { copyBtn.textContent = '📋 Скопировать код'; }, 2000);
      });
    });
  }
  var startBtn = $(g.prefix + '-start-btn');
  if (startBtn && !startBtn._init) {
    startBtn._init = true;
    startBtn.addEventListener('click', async function() {
      try { await apiFetch('/' + g.prefix + '/games/' + game.code + '/start?user_id=' + g.myUserId, { method: 'POST' }); }
      catch(e) { toast(e && e.detail || 'Ошибка', 'error'); }
    });
  }
}

function _cgRenderOpponents(g, state, containerId) {
  var el = $(containerId); if (!el) return;
  var uid = g.myUserId;
  var players = (state.players || []).filter(function(p) { return p.user_id !== uid; });
  el.innerHTML = players.map(function(p) {
    var isCurrent = p.user_id === state.current;
    var count = state.hands ? (state.hands[String(p.user_id)] || 0) : (p.hand_count || 0);
    var score = p.score !== undefined ? (' · ' + p.score + 'оч') : '';
    return '<div class="cg-opponent' + (isCurrent ? ' cg-current' : '') + '">'
      + '<div class="durak-opp-name">' + (isCurrent ? '→ ' : '') + p.display_name + score + '</div>'
      + '<div class="cg-opp-cards">'
      + Array.from({length: Math.min(count, 12)}, function() {
          return '<div class="cg-card-back-mini"></div>';
        }).join('') + (count > 12 ? '<span class="cg-extra">+' + (count-12) + '</span>' : '')
      + '</div></div>';
  }).join('');
}

// ════════════════════════════════════════════════════════════════
//  UNO
// ════════════════════════════════════════════════════════════════

var UNO_COLOR = { r: '#e63b2e', b: '#2563eb', g: '#16a34a', y: '#d97706' };
var UNO_COLOR_NAME = { r: '🔴', b: '🔵', g: '🟢', y: '🟡' };
var UNO_SCREENS = ['uno-setup','uno-lobby','uno-game'];

var _uno = _cgMakeGame('uno', UNO_SCREENS, null);

function _unoCardHtml(card, selected) {
  var cls = 'uno-card' + (selected ? ' selected' : '');
  if (card === 'wild' || card === 'wild4') {
    return '<div class="' + cls + ' uno-wild" data-card="' + card + '">'
      + '<div class="uno-wild-quarters"><span style="background:#e63b2e"></span><span style="background:#2563eb"></span>'
      + '<span style="background:#16a34a"></span><span style="background:#d97706"></span></div>'
      + '<div class="uno-card-center">' + (card === 'wild4' ? '+4' : '🌈') + '</div></div>';
  }
  var parts = card.split('-'); var color = parts[0]; var val = parts.slice(1).join('-');
  var label = val === 'skip' ? '⊘' : val === 'rev' ? '⇄' : val === 'draw2' ? '+2' : val;
  return '<div class="' + cls + '" style="background:' + (UNO_COLOR[color]||'#888') + '" data-card="' + card + '">'
    + '<span class="uno-corner tl">' + label + '</span>'
    + '<span class="uno-center-val">' + label + '</span>'
    + '<span class="uno-corner br">' + label + '</span>'
    + '</div>';
}

function initUnoMode() {
  _cgDisconnect(_uno); _uno.myUserId = state.user && state.user.id;
  _uno.initSetup = initUnoMode;
  _uno.onMsg = _unoOnMsg;
  _cgShowScreen(UNO_SCREENS, 'uno-setup');
  _unoInitSetup();
}

function _unoInitSetup() {
  var grp = $('uno-players-group');
  if (grp && !grp._init) {
    grp._init = true;
    grp.addEventListener('click', function(e) {
      var btn = e.target.closest('.durak-radio'); if (!btn) return;
      grp.querySelectorAll('.durak-radio').forEach(function(b) { b.classList.remove('active'); });
      btn.classList.add('active');
    });
  }
  var backBtn = $('uno-back-lobby');
  if (backBtn && !backBtn._init) {
    backBtn._init = true;
    backBtn.addEventListener('click', function() { _cgDisconnect(_uno); _cgShowScreen(UNO_SCREENS, null); _showChessScreen('games-lobby'); });
  }
  var createBtn = $('uno-create-btn');
  if (createBtn && !createBtn._init) {
    createBtn._init = true;
    createBtn.addEventListener('click', function() {
      var btn = document.querySelector('#uno-players-group .durak-radio.active');
      var mp = btn ? parseInt(btn.dataset.val) : 4;
      _cgCreateGame(_uno, { max_players: mp });
    });
  }
  var joinBtn = $('uno-join-btn');
  if (joinBtn && !joinBtn._init) {
    joinBtn._init = true;
    joinBtn.addEventListener('click', function() { _cgJoinGame(_uno); });
  }
  var joinInp = $('uno-join-input');
  if (joinInp && !joinInp._init) {
    joinInp._init = true;
    joinInp.addEventListener('keydown', function(e) { if (e.key === 'Enter') _cgJoinGame(_uno); });
    joinInp.addEventListener('input', function() { joinInp.value = joinInp.value.toUpperCase(); });
  }
}

function _unoOnMsg(msg) {
  if (msg.type === 'pong') return;
  if (msg.type === 'lobby') {
    _uno.game = msg.game;
    _cgUpdateLobbyPlayers(_uno, msg.players, msg.game);
    return;
  }
  if (msg.type === 'player_joined') {
    if (_uno.game) _cgUpdateLobbyPlayers(_uno, msg.players, _uno.game);
    return;
  }
  if (msg.type === 'error') { toast(msg.message, 'error'); return; }
  if (msg.type === 'state') {
    _uno.state = msg.state; _uno.myHand = msg.state.my_hand || [];
    _uno.selectedCard = null;
    if (msg.state.game_status === 'active') {
      _cgShowScreen(UNO_SCREENS, 'uno-game');
      _unoRender(msg.state);
    } else if (msg.state.game_status === 'waiting') {
      if (_uno.game) _cgUpdateLobbyPlayers(_uno, msg.state.players || [], _uno.game);
    }
    return;
  }
  if (msg.type === 'game_over') { _unoGameOver(msg); }
}

function _unoRender(state) {
  _cgRenderOpponents(_uno, state, 'uno-opponents');
  _unoRenderTopCard(state);
  _unoRenderHand(state);
  _unoRenderStatus(state);
  _unoRenderButtons(state);
  _unoInitGameBtns(state);
}

function _unoRenderTopCard(state) {
  var el = $('uno-top-card'); if (!el) return;
  el.innerHTML = _unoCardHtml(state.top_card, false);
  var bar = $('uno-color-bar'); if (!bar) return;
  var col = state.current_color;
  bar.style.background = UNO_COLOR[col] || '#888';
  bar.textContent = UNO_COLOR_NAME[col] || '';
  var deckEl = $('uno-deck-count'); if (deckEl) deckEl.textContent = state.deck_count || 0;
  var dir = $('uno-direction'); if (dir) dir.textContent = state.direction === 1 ? '↻' : '↺';
}

function _unoRenderHand(state) {
  var hand = $('uno-hand'); if (!hand) return;
  hand.innerHTML = '';
  var uid = _uno.myUserId;
  var isMyTurn = state.current === uid;
  _uno.myHand.forEach(function(card) {
    var isSel = _uno.selectedCard === card;
    var el = document.createElement('div');
    el.innerHTML = _unoCardHtml(card, isSel);
    var cardEl = el.firstChild;
    if (isMyTurn) {
      cardEl.draggable = true;
      cardEl.addEventListener('dragstart', function(e) { e.dataTransfer.setData('text/plain', card); });
      cardEl.addEventListener('click', function() {
        _uno.selectedCard = (_uno.selectedCard === card) ? null : card;
        _unoRenderHand(state); _unoRenderButtons(state);
      });
    }
    hand.appendChild(cardEl);
  });
}

function _unoRenderStatus(state) {
  var el = $('uno-status-text'); var dot = $('uno-status-dot'); if (!el) return;
  var uid = _uno.myUserId; var isMyTurn = state.current === uid;
  var phase = state.phase;
  var text = '', color = '#888';
  if (phase === 'finished') { text = 'Игра окончена!'; color = '#c96442'; }
  else if (phase === 'choose_color') {
    if (state.pending_wild_player === uid) { text = 'Выбери цвет!'; color = '#c96442'; }
    else { text = 'Соперник выбирает цвет…'; }
  } else if (isMyTurn) {
    text = state.draw_pending > 0 ? ('⚠ Возьми ' + state.draw_pending + ' карты или покрой') : '→ Ваш ход!';
    color = '#c96442';
  } else {
    var cur = (state.players || []).find(function(p) { return p.user_id === state.current; });
    text = (cur ? cur.display_name : '?') + ' ходит…';
  }
  el.textContent = text;
  if (dot) dot.style.background = color;
}

function _unoRenderButtons(state) {
  var uid = _uno.myUserId; var isMyTurn = state.current === uid;
  var hasSel = !!_uno.selectedCard;
  var playBtn = $('uno-play-btn'); var drawBtn = $('uno-draw-btn'); var unoBtn = $('uno-uno-btn');
  if (playBtn) playBtn.style.display = (isMyTurn && hasSel) ? '' : 'none';
  if (drawBtn) drawBtn.style.display = isMyTurn ? '' : 'none';
  if (unoBtn) unoBtn.style.display = (_uno.myHand.length <= 2 && isMyTurn) ? '' : 'none';
}

function _unoInitGameBtns(state) {
  var playBtn = $('uno-play-btn');
  if (playBtn && !playBtn._init) {
    playBtn._init = true;
    playBtn.addEventListener('click', function() {
      var card = _uno.selectedCard; if (!card) return;
      if (card === 'wild' || card === 'wild4') { _unoShowColorPicker(card); return; }
      _uno.selectedCard = null; _cgSend(_uno, { type: 'play', card: card });
    });
  }
  var drawBtn = $('uno-draw-btn');
  if (drawBtn && !drawBtn._init) {
    drawBtn._init = true;
    drawBtn.addEventListener('click', function() { _cgSend(_uno, { type: 'draw' }); });
  }
  var unoBtn = $('uno-uno-btn');
  if (unoBtn && !unoBtn._init) {
    unoBtn._init = true;
    unoBtn.addEventListener('click', function() { _cgSend(_uno, { type: 'uno' }); toast('UNO!'); });
  }
  // Color picker
  var picker = $('uno-color-picker');
  if (picker && !picker._init) {
    picker._init = true;
    picker.querySelectorAll('.uno-cp-btn').forEach(function(btn) {
      btn.addEventListener('click', function() {
        var color = btn.dataset.color;
        picker.style.display = 'none';
        var card = _uno._pendingWildCard;
        _uno.selectedCard = null; _uno._pendingWildCard = null;
        _cgSend(_uno, { type: 'play', card: card, color: color });
      });
    });
  }
  var goNew = $('uno-go-new');
  if (goNew && !goNew._init) {
    goNew._init = true;
    goNew.addEventListener('click', function() {
      var g = $('uno-gameover'); if (g) g.style.display = 'none';
      _cgDisconnect(_uno); _cgShowScreen(UNO_SCREENS, 'uno-setup'); initUnoMode();
    });
  }
  var goLobby = $('uno-go-lobby');
  if (goLobby && !goLobby._init) {
    goLobby._init = true;
    goLobby.addEventListener('click', function() { _cgDisconnect(_uno); _cgShowScreen(UNO_SCREENS, null); _showChessScreen('games-lobby'); });
  }
}

function _unoShowColorPicker(card) {
  _uno._pendingWildCard = card;
  var picker = $('uno-color-picker'); if (picker) picker.style.display = '';
}

function _unoGameOver(msg) {
  var uid = _uno.myUserId; var isWinner = msg.winner_id === uid;
  var goEl = $('uno-gameover'); if (!goEl) return;
  var icon = $('uno-go-icon'); if (icon) icon.textContent = isWinner ? '🏆' : '😔';
  var title = $('uno-go-title'); if (title) title.textContent = isWinner ? 'Победа!' : 'Ты проиграл!';
  var sub = $('uno-go-sub'); if (sub) sub.textContent = 'Победитель: ' + msg.winner_name;
  goEl.style.display = '';
}

// ════════════════════════════════════════════════════════════════
//  101
// ════════════════════════════════════════════════════════════════

var G101_SUIT_COLOR = { '♠': '#111', '♣': '#111', '♥': '#c00', '♦': '#c00' };
var G101_SCREENS = ['g101-setup','g101-lobby','g101-game'];

var _g101 = _cgMakeGame('game101', G101_SCREENS, null);

function _g101CardHtml(card, selected, highlight) {
  var rank = card.startsWith('10') ? '10' : card.slice(0, -1);
  var suit = card.slice(-1);
  var color = G101_SUIT_COLOR[suit] || '#111';
  var cls = 'durak-card durak-card-' + (['♥','♦'].includes(suit) ? 'red' : 'black')
    + (selected ? ' selected' : '') + (highlight ? ' clickable-target' : '');
  return '<div class="' + cls + '" data-card="' + card + '">'
    + '<span class="dc-rank">' + rank + '</span>'
    + '<span class="dc-suit">' + suit + '</span></div>';
}

function initG101Mode() {
  _cgDisconnect(_g101); _g101.myUserId = state.user && state.user.id;
  _g101.initSetup = initG101Mode;
  _g101.onMsg = _g101OnMsg;
  _cgShowScreen(G101_SCREENS, 'g101-setup');
  _g101InitSetup();
}

function _g101InitSetup() {
  var grp = $('g101-players-group');
  if (grp && !grp._init) {
    grp._init = true;
    grp.addEventListener('click', function(e) {
      var btn = e.target.closest('.durak-radio'); if (!btn) return;
      grp.querySelectorAll('.durak-radio').forEach(function(b) { b.classList.remove('active'); });
      btn.classList.add('active');
    });
  }
  var backBtn = $('g101-back-lobby');
  if (backBtn && !backBtn._init) {
    backBtn._init = true;
    backBtn.addEventListener('click', function() { _cgDisconnect(_g101); _cgShowScreen(G101_SCREENS, null); _showChessScreen('games-lobby'); });
  }
  var createBtn = $('g101-create-btn');
  if (createBtn && !createBtn._init) {
    createBtn._init = true;
    createBtn.addEventListener('click', function() {
      var btn = document.querySelector('#g101-players-group .durak-radio.active');
      var mp = btn ? parseInt(btn.dataset.val) : 2;
      _cgCreateGame(_g101, { max_players: mp });
    });
  }
  var joinBtn = $('g101-join-btn');
  if (joinBtn && !joinBtn._init) {
    joinBtn._init = true;
    joinBtn.addEventListener('click', function() { _cgJoinGame(_g101); });
  }
  var joinInp = $('g101-join-input');
  if (joinInp && !joinInp._init) {
    joinInp._init = true;
    joinInp.addEventListener('keydown', function(e) { if (e.key === 'Enter') _cgJoinGame(_g101); });
    joinInp.addEventListener('input', function() { joinInp.value = joinInp.value.toUpperCase(); });
  }
}

function _g101OnMsg(msg) {
  if (msg.type === 'pong') return;
  if (msg.type === 'lobby') { _g101.game = msg.game; _cgUpdateLobbyPlayers(_g101, msg.players, msg.game); return; }
  if (msg.type === 'player_joined') { if (_g101.game) _cgUpdateLobbyPlayers(_g101, msg.players, _g101.game); return; }
  if (msg.type === 'error') { toast(msg.message, 'error'); return; }
  if (msg.type === 'draw_continue') { toast('Не покрыл — тяни ещё!'); return; }
  if (msg.type === 'round_over') {
    toast('Раунд окончен! Победитель раунда: ' + msg.winner_name);
    _g101RenderScores(msg.scores, msg);
    var nrBtn = $('g101-next-round-btn'); if (nrBtn) nrBtn.style.display = '';
    return;
  }
  if (msg.type === 'state') {
    _g101.state = msg.state; _g101.myHand = msg.state.my_hand || [];
    _g101.selectedCard = null;
    if (msg.state.game_status === 'active') {
      _cgShowScreen(G101_SCREENS, 'g101-game');
      _g101Render(msg.state);
    } else if (msg.state.game_status === 'waiting') {
      if (_g101.game) _cgUpdateLobbyPlayers(_g101, msg.state.players || [], _g101.game);
    }
    return;
  }
  if (msg.type === 'game_over') { _g101GameOver(msg); }
}

function _g101Render(state) {
  _cgRenderOpponents(_g101, state, 'g101-opponents');
  _g101RenderTop(state);
  _g101RenderHand(state);
  _g101RenderStatus(state);
  _g101RenderButtons(state);
  _g101InitGameBtns(state);
  _g101RenderScores(state.scores, state);
}

function _g101RenderTop(state) {
  var el = $('g101-top-card'); if (el) el.innerHTML = _g101CardHtml(state.top_card, false, false);
  var bar = $('g101-suit-bar'); if (bar) {
    var suit = state.current_suit;
    bar.textContent = suit;
    bar.style.color = G101_SUIT_COLOR[suit] || '#111';
  }
  var dk = $('g101-deck-count'); if (dk) dk.textContent = state.deck_count || 0;
}

function _g101RenderHand(state) {
  var hand = $('g101-hand'); if (!hand) return;
  hand.innerHTML = '';
  var uid = _g101.myUserId; var isMyTurn = state.current === uid;
  _g101.myHand.forEach(function(card) {
    var isSel = _g101.selectedCard === card;
    var el = document.createElement('div');
    el.innerHTML = _g101CardHtml(card, isSel, false);
    var cardEl = el.firstChild;
    if (isMyTurn) {
      cardEl.draggable = true;
      cardEl.addEventListener('dragstart', function(e) { e.dataTransfer.setData('text/plain', card); });
      cardEl.addEventListener('click', function() {
        _g101.selectedCard = (_g101.selectedCard === card) ? null : card;
        _g101RenderHand(state); _g101RenderButtons(state);
      });
    }
    hand.appendChild(cardEl);
  });
}

function _g101RenderStatus(state) {
  var el = $('g101-status-text'); var dot = $('g101-status-dot'); if (!el) return;
  var uid = _g101.myUserId; var isMyTurn = state.current === uid;
  var text = '', color = '#888';
  if (state.phase === 'finished') { text = 'Игра окончена!'; color = '#c96442'; }
  else if (state.phase === 'finished_round') { text = 'Раунд окончен — смотри очки!'; color = '#5a8a5a'; }
  else if (state.phase === 'choose_suit') {
    if (state.pending_q_player === uid) { text = 'Выбери масть (дама)!'; color = '#c96442'; }
    else { text = 'Соперник выбирает масть…'; }
  } else if (isMyTurn) {
    if (state.draw6_pending) text = '⚠ Тяни карты пока не покроешь масть или 6!';
    else if (state.draw5_pending) text = '⚠ Возьми 5 карт (♠K)!';
    else text = '→ Ваш ход!';
    color = '#c96442';
  } else {
    var cur = (state.players || []).find(function(p) { return p.user_id === state.current; });
    text = (cur ? cur.display_name : '?') + ' ходит…';
  }
  el.textContent = text; if (dot) dot.style.background = color;
}

function _g101RenderButtons(state) {
  var uid = _g101.myUserId; var isMyTurn = state.current === uid;
  var hasSel = !!_g101.selectedCard;
  var playBtn    = $('g101-play-btn');
  var drawBtn    = $('g101-draw-btn');
  var drawOneBtn = $('g101-draw-one-btn');
  var nrBtn      = $('g101-next-round-btn');
  if (playBtn) playBtn.style.display = (isMyTurn && hasSel && state.phase === 'play') ? '' : 'none';
  if (drawBtn) drawBtn.style.display = (isMyTurn && !state.draw6_pending && !state.draw5_pending && state.phase === 'play') ? '' : 'none';
  if (drawOneBtn) drawOneBtn.style.display = (isMyTurn && (state.draw6_pending || state.draw5_pending)) ? '' : 'none';
  if (nrBtn) nrBtn.style.display = (state.phase === 'finished_round' && uid === state.current) ? '' : 'none';
}

function _g101RenderScores(scores, state) {
  var el = $('g101-scores'); if (!el) return;
  if (!scores || !Object.keys(scores).length) { el.innerHTML = ''; return; }
  var players = (state && state.players) || _g101.state && _g101.state.players || [];
  el.innerHTML = '<div class="g101-score-row">' + Object.entries(scores).map(function(kv) {
    var pid = kv[0]; var sc = kv[1];
    var p = players.find(function(pl) { return String(pl.user_id) === pid; });
    var name = p ? p.display_name : pid;
    var danger = sc >= 90 ? ' g101-score-danger' : sc >= 70 ? ' g101-score-warn' : '';
    return '<span class="g101-score-item' + danger + '">' + name + ': <b>' + sc + '</b></span>';
  }).join('') + '</div>';
}

function _g101InitGameBtns(state) {
  var playBtn = $('g101-play-btn');
  if (playBtn && !playBtn._init) {
    playBtn._init = true;
    playBtn.addEventListener('click', function() {
      var card = _g101.selectedCard; if (!card) return;
      var rank = card.startsWith('10') ? '10' : card.slice(0, -1);
      if (rank === 'Q') { _g101ShowSuitPicker(card); return; }
      _g101.selectedCard = null; _cgSend(_g101, { type: 'play', card: card });
    });
  }
  var drawBtn = $('g101-draw-btn');
  if (drawBtn && !drawBtn._init) {
    drawBtn._init = true;
    drawBtn.addEventListener('click', function() { _cgSend(_g101, { type: 'draw_pass' }); });
  }
  var drawOneBtn = $('g101-draw-one-btn');
  if (drawOneBtn && !drawOneBtn._init) {
    drawOneBtn._init = true;
    drawOneBtn.addEventListener('click', function() { _cgSend(_g101, { type: 'draw_one' }); });
  }
  var nrBtn = $('g101-next-round-btn');
  if (nrBtn && !nrBtn._init) {
    nrBtn._init = true;
    nrBtn.addEventListener('click', function() { _cgSend(_g101, { type: 'new_round' }); nrBtn.style.display = 'none'; });
  }
  var picker = $('g101-suit-picker');
  if (picker && !picker._init) {
    picker._init = true;
    picker.querySelectorAll('.g101-suit-btn').forEach(function(btn) {
      btn.addEventListener('click', function() {
        picker.style.display = 'none';
        var card = _g101._pendingQueenCard; var suit = btn.dataset.suit;
        _g101.selectedCard = null; _g101._pendingQueenCard = null;
        _cgSend(_g101, { type: 'play', card: card, suit: suit });
      });
    });
  }
  var goNew = $('g101-go-new');
  if (goNew && !goNew._init) {
    goNew._init = true;
    goNew.addEventListener('click', function() {
      var g = $('g101-gameover'); if (g) g.style.display = 'none';
      _cgDisconnect(_g101); _cgShowScreen(G101_SCREENS, 'g101-setup'); initG101Mode();
    });
  }
  var goLobby = $('g101-go-lobby');
  if (goLobby && !goLobby._init) {
    goLobby._init = true;
    goLobby.addEventListener('click', function() { _cgDisconnect(_g101); _cgShowScreen(G101_SCREENS, null); _showChessScreen('games-lobby'); });
  }
}

function _g101ShowSuitPicker(card) {
  _g101._pendingQueenCard = card;
  var picker = $('g101-suit-picker'); if (picker) picker.style.display = '';
}

function _g101GameOver(msg) {
  var uid = _g101.myUserId;
  var goEl = $('g101-gameover'); if (!goEl) return;
  var isLoser = msg.loser_id === uid; var isWinner = msg.winner_id === uid;
  var icon = $('g101-go-icon'); if (icon) icon.textContent = isLoser ? '🤡' : isWinner ? '🏆' : '🎴';
  var title = $('g101-go-title'); if (title) title.textContent = isLoser ? 'Ты набрал 101! Проигрыш!' : (isWinner ? 'Победа в раунде!' : 'Игра окончена');
  var sub = $('g101-go-sub');
  if (sub) {
    var scLines = Object.entries(msg.scores || {}).map(function(kv) {
      return 'Игрок ' + kv[0] + ': ' + kv[1] + ' очков';
    }).join('\n');
    sub.textContent = 'Дурак: ' + msg.loser_name + '\n' + scLines;
  }
  goEl.style.display = '';
}
