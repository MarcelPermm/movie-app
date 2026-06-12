"""101 card game logic — pure functions.
Rules variant:
  6   = next player draws cards until matching suit or another 6
  A   = next player skips
  Q   = current player declares new suit
  K♠  = next player draws 5 cards
  Others: match suit or rank
Scoring: 6-10=face, J=2, Q=3, K=4, A=11
First to 101 total points loses.
"""
import random, copy

SUITS = ['♠','♥','♦','♣']
RANKS = ['6','7','8','9','10','J','Q','K','A']

RANK_SCORE = {'6':6,'7':7,'8':8,'9':9,'10':10,'J':2,'Q':3,'K':4,'A':11}

def _make_deck() -> list:
    deck = [r+s for s in SUITS for r in RANKS]
    random.shuffle(deck)
    return deck

def _parse(card):
    if card.startswith('10'):
        return '10', card[2:]
    return card[:-1], card[-1]

def _rank(card):  return _parse(card)[0]
def _suit(card):  return _parse(card)[1]

def _can_play(card, top, current_suit) -> bool:
    r, s = _parse(card)
    tr, _ = _parse(top)
    if r == 'Q': return True      # Дама — меняет масть, играется всегда
    if r == 'A': return True      # Туз — любая масть (пропуск)
    if s == current_suit: return True
    if r == tr: return True
    return False

def _next_idx(state, skip=0):
    order = state['active']
    idx = order.index(state['current'])
    step = state['direction'] * (1 + skip)
    return (idx + step) % len(order)

def _next_player(state, skip=0):
    return state['active'][_next_idx(state, skip)]

def init_game(player_ids: list) -> dict:
    deck = _make_deck()
    hands = {str(p): [] for p in player_ids}
    for _ in range(5):
        for p in player_ids:
            hands[str(p)].append(deck.pop())
    top = deck.pop()
    # Don't start on special cards
    while _rank(top) in ('6','A','Q') or top == 'K♠':
        deck.insert(0, top)
        random.shuffle(deck)
        top = deck.pop()
    scores = {str(p): 0 for p in player_ids}
    return {
        'deck': deck,
        'discard': [top],
        'top_card': top,
        'current_suit': _suit(top),
        'hands': hands,
        'turn_order': list(player_ids),
        'active': list(player_ids),
        'current': player_ids[0],
        'direction': 1,
        'draw6_pending': False,   # активная шестёрка (нужно тянуть)
        'draw5_pending': False,   # King of Spades
        'phase': 'play',          # play | choose_suit | finished
        'winner': None,
        'scores': scores,
        'round': 1,
        'pending_q_player': None,
    }

def do_play(state: dict, player_id: int, card: str, chosen_suit: str = None) -> tuple:
    if player_id != state['current']:
        return state, 'Сейчас не ваш ход'
    hand = list(state['hands'].get(str(player_id), []))
    if card not in hand:
        return state, 'Этой карты нет в руке'

    # Draw6 pending: can only cover with same suit or another 6
    if state.get('draw6_pending'):
        r, s = _parse(card)
        if not (s == state['current_suit'] or r == '6'):
            return state, 'Нужно покрыть 6 той же масти или ещё одной 6'

    if not _can_play(card, state['top_card'], state['current_suit']):
        return state, 'Эту карту нельзя сыграть'

    s = copy.deepcopy(state)
    s['hands'][str(player_id)].remove(card)
    s['discard'].append(card)
    s['top_card'] = card
    s['draw6_pending'] = False
    s['draw5_pending'] = False

    r, suit = _parse(card)

    if r == 'Q':
        # Дама: игрок выбирает новую масть
        if chosen_suit and chosen_suit in SUITS:
            s['current_suit'] = chosen_suit
            s['phase'] = 'play'
            s['current'] = _next_player(s)
        else:
            s['phase'] = 'choose_suit'
            s['pending_q_player'] = player_id
            # Не переходим к следующему игроку пока не выбрана масть
            return _check_win(s, player_id), None
    elif r == 'A':
        # Туз: пропуск следующего игрока
        s['current_suit'] = suit
        s['current'] = _next_player(s, skip=1)
    elif r == '6':
        # Следующий должен тянуть пока не покроет
        s['current_suit'] = suit
        s['draw6_pending'] = True
        s['current'] = _next_player(s)
    elif card == 'K♠':
        s['current_suit'] = '♠'
        s['draw5_pending'] = True
        s['current'] = _next_player(s)
    else:
        s['current_suit'] = suit
        s['current'] = _next_player(s)

    return _check_win(s, player_id), None

def do_choose_suit(state: dict, player_id: int, suit: str) -> tuple:
    if state['phase'] != 'choose_suit':
        return state, 'Сейчас не выбор масти'
    if state['pending_q_player'] != player_id:
        return state, 'Не ваш выбор'
    if suit not in SUITS:
        return state, 'Неверная масть'
    s = copy.deepcopy(state)
    s['current_suit'] = suit
    s['phase'] = 'play'
    s['pending_q_player'] = None
    s['current'] = _next_player(s)
    return s, None

def do_draw_one(state: dict, player_id: int) -> tuple:
    """Draw one card trying to cover a 6. Returns (new_state, covered, error)."""
    if player_id != state['current']:
        return state, False, 'Сейчас не ваш ход'
    if not state.get('draw6_pending') and not state.get('draw5_pending'):
        return state, False, 'Нет обязательного взятия'

    s = copy.deepcopy(state)
    if not s['deck']:
        top = s['discard'].pop()
        s['deck'] = s['discard'][:]
        random.shuffle(s['deck'])
        s['discard'] = [top]
    if not s['deck']:
        return s, True, None  # no cards — skip

    card = s['deck'].pop()
    s['hands'][str(player_id)].append(card)
    r, suit = _parse(card)

    if s.get('draw5_pending'):
        # Берём 5 подряд (вызываем 5 раз через WS или считаем сразу)
        count = len(s['hands'][str(player_id)]) - 1  # minus the one just drawn
        # Simplify: take all 5 at once
        for _ in range(4):
            if s['deck']:
                s['hands'][str(player_id)].append(s['deck'].pop())
        s['draw5_pending'] = False
        s['current'] = _next_player(s)
        return s, True, None

    if suit == s['current_suit'] or r == '6':
        # Покрыл!
        s['draw6_pending'] = False
        s['current'] = _next_player(s)
        return s, True, None
    # Не покрыл — продолжаем тянуть
    return s, False, None

def do_skip_draw(state: dict, player_id: int) -> tuple:
    """Player can't cover — take all pending and skip."""
    if player_id != state['current']:
        return state, 'Сейчас не ваш ход'
    s = copy.deepcopy(state)
    n = 5 if s.get('draw5_pending') else 0
    # For draw6_pending: player already drew until done; this is just end-of-draw
    s['draw6_pending'] = False
    s['draw5_pending'] = False
    if n > 0:
        for _ in range(n):
            if s['deck']:
                s['hands'][str(player_id)].append(s['deck'].pop())
    s['current'] = _next_player(s)
    return s, None

def do_draw_pass(state: dict, player_id: int) -> tuple:
    """Normal draw (can't play) — draw 1 then pass."""
    if player_id != state['current']:
        return state, 'Сейчас не ваш ход'
    if state.get('draw6_pending') or state.get('draw5_pending'):
        return state, 'Нужно взять обязательные карты'
    s = copy.deepcopy(state)
    if not s['deck'] and len(s['discard']) > 1:
        # Перетасовать сброс (кроме верхней карты) обратно в колоду
        top = s['discard'].pop()
        s['deck'] = s['discard'][:]
        random.shuffle(s['deck'])
        s['discard'] = [top]
    if s['deck']:
        s['hands'][str(player_id)].append(s['deck'].pop())
    s['current'] = _next_player(s)
    return s, None

def _check_win(state, player_id):
    s = copy.deepcopy(state)
    if not s['hands'].get(str(player_id)):
        # Round over — count scores
        for pid_str, hand in s['hands'].items():
            pts = sum(RANK_SCORE.get(_rank(c), 0) for c in hand)
            s['scores'][pid_str] = s['scores'].get(pid_str, 0) + pts
        # Check if anyone hit 101+
        loser = None
        for pid_str, sc in s['scores'].items():
            if sc >= 101:
                if loser is None or sc > s['scores'][str(loser)]:
                    loser = int(pid_str)
        if loser:
            s['phase'] = 'finished'
            s['winner'] = player_id   # round winner
            s['loser'] = loser
        else:
            s['phase'] = 'finished_round'
            s['winner'] = player_id
    return s

def start_new_round(state: dict) -> dict:
    s = copy.deepcopy(state)
    player_ids = s['turn_order']
    deck = _make_deck()
    hands = {str(p): [] for p in player_ids}
    for _ in range(5):
        for p in player_ids:
            hands[str(p)].append(deck.pop())
    top = deck.pop()
    while _rank(top) in ('6','A','Q') or top == 'K♠':
        deck.insert(0, top)
        random.shuffle(deck)
        top = deck.pop()
    # Next first player = round winner of last round
    winner_idx = player_ids.index(s['winner']) if s['winner'] in player_ids else 0
    new_order = player_ids[winner_idx:] + player_ids[:winner_idx]
    s.update({
        'deck': deck, 'discard': [top], 'top_card': top,
        'current_suit': _suit(top), 'hands': hands,
        'active': list(player_ids), 'current': new_order[0],
        'direction': 1, 'draw6_pending': False, 'draw5_pending': False,
        'phase': 'play', 'winner': None, 'round': s['round'] + 1,
        'pending_q_player': None,
    })
    return s

def public_state(state: dict, viewer_id: int, players_meta: list) -> dict:
    hands_view = {}
    for pid_str, hand in state['hands'].items():
        pid = int(pid_str)
        hands_view[pid_str] = hand if pid == viewer_id else len(hand)
    return {
        'top_card': state['top_card'],
        'current_suit': state['current_suit'],
        'deck_count': len(state['deck']),
        'current': state['current'],
        'direction': state['direction'],
        'draw6_pending': state.get('draw6_pending', False),
        'draw5_pending': state.get('draw5_pending', False),
        'phase': state['phase'],
        'winner': state.get('winner'),
        'loser': state.get('loser'),
        'scores': state.get('scores', {}),
        'round': state.get('round', 1),
        'pending_q_player': state.get('pending_q_player'),
        'hands': hands_view,
        'players': [{'user_id': p['user_id'], 'display_name': p['display_name'],
                     'seat': p['seat'],
                     'hand_count': len(state['hands'].get(str(p['user_id']),[])),
                     'score': state.get('scores',{}).get(str(p['user_id']),0),
                     } for p in players_meta],
    }
