"""UNO card game logic — pure functions."""
import random, copy

COLORS = ['r','b','g','y']
COLOR_NAMES = {'r':'Красный','b':'Синий','g':'Зелёный','y':'Жёлтый'}
NUMS = ['0','1','2','3','4','5','6','7','8','9']
ACTIONS = ['skip','rev','draw2']
WILDS = ['wild','wild4']

def _make_deck() -> list:
    deck = []
    for c in COLORS:
        deck.append(f'{c}-0')
        for n in NUMS[1:]:   deck += [f'{c}-{n}', f'{c}-{n}']
        for a in ACTIONS:    deck += [f'{a}-{c}', f'{a}-{c}']
    deck += ['wild', 'wild', 'wild', 'wild',
             'wild4','wild4','wild4','wild4']
    random.shuffle(deck)
    return deck

def _is_wild(card): return card in WILDS or card.startswith('wild')
def _color(card):
    if _is_wild(card): return None
    return card.split('-')[0] if '-' in card else None
def _value(card):
    if _is_wild(card): return card
    return card.split('-',1)[1] if '-' in card else card

def _can_play(card, top_card, current_color) -> bool:
    if _is_wild(card): return True
    c, v = _color(card), _value(card)
    tc, tv = _color(top_card), _value(top_card)
    if c == current_color: return True
    if v == tv: return True
    return False

def _next_idx(state, skip=0):
    order = state['active_order']
    idx = order.index(state['current'])
    step = state['direction'] * (1 + skip)
    return (idx + step) % len(order)

def _next_player(state, skip=0):
    return state['active_order'][_next_idx(state, skip)]

def init_game(player_ids: list) -> dict:
    deck = _make_deck()
    hands = {str(p): [] for p in player_ids}
    for _ in range(7):
        for p in player_ids:
            hands[str(p)].append(deck.pop())
    # First card — skip wilds
    top = deck.pop()
    while _is_wild(top):
        deck.insert(0, top)
        random.shuffle(deck)
        top = deck.pop()
    return {
        'deck': deck,
        'discard': [top],
        'top_card': top,
        'current_color': _color(top),
        'hands': hands,
        'turn_order': list(player_ids),
        'active_order': list(player_ids),
        'current': player_ids[0],
        'direction': 1,
        'draw_pending': 0,    # pending draws from +2/+4 stack
        'must_draw': False,   # current player must draw
        'uno_said': [],       # players who said UNO
        'phase': 'play',      # play | choose_color | finished
        'winner': None,
        'pending_wild_player': None,
    }

def do_play(state: dict, player_id: int, card: str, chosen_color: str = None) -> tuple:
    hand = list(state['hands'].get(str(player_id), []))
    if player_id != state['current']:
        return state, 'Сейчас не ваш ход'
    if card not in hand:
        return state, 'Этой карты нет в руке'
    if state['draw_pending'] > 0:
        # Must play stacking card or draw
        tv = _value(state['top_card'])
        cv = _value(card)
        stack_ok = (tv == 'draw2' and cv == 'draw2') or (tv == 'wild4' and card == 'wild4')
        if not stack_ok:
            return state, 'Нужно взять карты или подложить такую же'
    if not _can_play(card, state['top_card'], state['current_color']):
        return state, 'Эту карту нельзя сыграть'

    s = copy.deepcopy(state)
    s['hands'][str(player_id)].remove(card)
    s['discard'].append(card)
    s['top_card'] = card
    s['uno_said'] = [u for u in s['uno_said'] if u != player_id]

    val = _value(card)
    skip_next = False

    if card == 'wild4':
        s['draw_pending'] = (s['draw_pending'] or 0) + 4
        s['phase'] = 'choose_color'
        s['pending_wild_player'] = player_id
    elif card == 'wild':
        s['phase'] = 'choose_color'
        s['pending_wild_player'] = player_id
    elif val == 'draw2':
        s['draw_pending'] = (s['draw_pending'] or 0) + 2
        skip_next = True
        s['current_color'] = _color(card)
    elif val == 'skip':
        skip_next = True
        s['current_color'] = _color(card)
    elif val == 'rev':
        s['direction'] *= -1
        s['current_color'] = _color(card)
        if len(s['active_order']) == 2:
            skip_next = True
    else:
        s['current_color'] = _color(card)

    # Check win
    if not s['hands'][str(player_id)]:
        s['phase'] = 'finished'
        s['winner'] = player_id
        return s, None

    if s['phase'] == 'play':
        s['current'] = _next_player(s, skip=1 if skip_next else 0)
        if skip_next and s['draw_pending'] > 0:
            # next player must draw
            pass

    return s, None

def do_choose_color(state: dict, player_id: int, color: str) -> tuple:
    if state['phase'] != 'choose_color':
        return state, 'Сейчас не выбор цвета'
    if state['pending_wild_player'] != player_id:
        return state, 'Не ваш выбор'
    if color not in COLORS:
        return state, 'Неверный цвет'
    s = copy.deepcopy(state)
    s['current_color'] = color
    s['phase'] = 'play'
    s['pending_wild_player'] = None
    val = _value(s['top_card'])
    if val == 'wild4':
        s['current'] = _next_player(s, skip=1)
    else:
        s['current'] = _next_player(s)
    return s, None

def do_draw(state: dict, player_id: int) -> tuple:
    if player_id != state['current']:
        return state, 'Сейчас не ваш ход'
    s = copy.deepcopy(state)
    if not s['deck']:
        # Reshuffle discard into deck
        top = s['discard'].pop()
        s['deck'] = s['discard'][:]
        random.shuffle(s['deck'])
        s['discard'] = [top]
    if not s['deck']:
        return s, 'Колода пуста'
    n = s['draw_pending'] if s['draw_pending'] > 0 else 1
    for _ in range(min(n, len(s['deck']))):
        s['hands'][str(player_id)].append(s['deck'].pop())
    s['draw_pending'] = 0
    s['current'] = _next_player(s)
    return s, None

def do_say_uno(state: dict, player_id: int) -> tuple:
    s = copy.deepcopy(state)
    if len(s['hands'].get(str(player_id), [])) <= 2:
        if player_id not in s['uno_said']:
            s['uno_said'].append(player_id)
    return s, None

def public_state(state: dict, viewer_id: int, players_meta: list) -> dict:
    hands_view = {}
    for pid_str, hand in state['hands'].items():
        pid = int(pid_str)
        hands_view[pid_str] = hand if pid == viewer_id else len(hand)
    return {
        'top_card': state['top_card'],
        'current_color': state['current_color'],
        'deck_count': len(state['deck']),
        'current': state['current'],
        'direction': state['direction'],
        'draw_pending': state['draw_pending'],
        'phase': state['phase'],
        'winner': state['winner'],
        'uno_said': state['uno_said'],
        'pending_wild_player': state.get('pending_wild_player'),
        'hands': hands_view,
        'players': [{'user_id': p['user_id'], 'display_name': p['display_name'],
                     'seat': p['seat'], 'hand_count': len(state['hands'].get(str(p['user_id']),[])),
                     } for p in players_meta],
    }
