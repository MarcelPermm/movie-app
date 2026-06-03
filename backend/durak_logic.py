"""
Durak card game logic — pure functions, no DB/IO.
"""
import random
import copy

SUITS = ['♠', '♥', '♦', '♣']
RED_SUITS = {'♥', '♦'}

def make_deck(deck_size: int) -> list:
    if deck_size == 24:
        ranks = ['9', '10', 'J', 'Q', 'K', 'A']
    elif deck_size == 36:
        ranks = ['6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']
    else:  # 52
        ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']
    deck = [r + s for s in SUITS for r in ranks]
    random.shuffle(deck)
    return deck

def parse_card(card: str) -> tuple:
    """'A♠'→('A','♠'), '10♥'→('10','♥')"""
    if card.startswith('10'):
        return '10', card[2]
    return card[:-1], card[-1]

def card_rank_order(deck_size: int) -> list:
    if deck_size == 24:
        return ['9', '10', 'J', 'Q', 'K', 'A']
    if deck_size == 36:
        return ['6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']
    return ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']

def card_value(rank: str, deck_size: int) -> int:
    order = card_rank_order(deck_size)
    return order.index(rank) if rank in order else -1

def can_beat(attack: str, defense: str, trump_suit: str, deck_size: int) -> bool:
    ar, as_ = parse_card(attack)
    dr, ds  = parse_card(defense)
    if as_ == ds:
        return card_value(dr, deck_size) > card_value(ar, deck_size)
    if ds == trump_suit and as_ != trump_suit:
        return True
    return False

def ranks_on_table(table: list) -> set:
    ranks = set()
    for slot in table:
        if slot['attack']:  ranks.add(parse_card(slot['attack'])[0])
        if slot['defense']: ranks.add(parse_card(slot['defense'])[0])
    return ranks

def active_players(state: dict) -> list:
    return [p for p in state['turn_order'] if p not in state['finished_players']]

def get_attackers(state: dict) -> list:
    """Who can throw cards right now."""
    act = active_players(state)
    defender = state['defender']
    if state['neighbors_only']:
        turn_order = state['turn_order']
        d_idx = turn_order.index(defender)
        # attacker = player before defender in turn order
        prev_idx = (d_idx - 1) % len(turn_order)
        next_idx = (d_idx + 1) % len(turn_order)
        candidates = {turn_order[prev_idx], turn_order[next_idx]}
        return [p for p in act if p in candidates and p != defender]
    else:
        return [p for p in act if p != defender]

def _next_active(state: dict, start_id: int, skip: int = None) -> int:
    turn_order = state['turn_order']
    finished = state['finished_players']
    idx = turn_order.index(start_id)
    for i in range(1, len(turn_order)):
        candidate = turn_order[(idx + i) % len(turn_order)]
        if candidate not in finished and candidate != skip:
            return candidate
    return None

# ── Init ──────────────────────────────────────────────────────────────────────

def init_game(player_ids: list, deck_size: int, variant: str, neighbors_only: bool) -> dict:
    deck = make_deck(deck_size)
    # Trump = last card of deck (shown face-up under deck)
    trump_card = deck[-1]
    _, trump_suit = parse_card(trump_card)

    # Deal 6 cards each (from top)
    hands = {str(pid): [] for pid in player_ids}
    for _ in range(6):
        for pid in player_ids:
            if deck:
                card = deck.pop(0)
                if card == trump_card and not deck:
                    # Don't draw the trump card yet — keep it as the last card
                    # Actually standard deal just puts trump back at bottom;
                    # we already put trump at deck[-1]. If deck empties during
                    # deal just give it.
                    pass
                hands[str(pid)].append(card)

    # If trump was dealt, still reveal it (it's in someone's hand)
    # In standard durak: trump stays face-up at the BOTTOM; we simulated it as last card
    # but we already dealt 6 each. Let's just keep trump_card as reference.

    # Find first attacker: lowest trump card
    first_attacker = _find_first_attacker(hands, trump_suit, deck_size, player_ids)
    fa_idx = player_ids.index(first_attacker)
    turn_order = player_ids[fa_idx:] + player_ids[:fa_idx]

    attacker = turn_order[0]
    defender = turn_order[1 % len(turn_order)]

    return {
        'deck':             deck,
        'trump_suit':       trump_suit,
        'trump_card':       trump_card,
        'discard':          [],
        'hands':            hands,
        'table':            [],
        'turn_order':       turn_order,
        'attacker':         attacker,
        'defender':         defender,
        'phase':            'attack',   # attack | defense | throwing | finished
        'done_attackers':   [],
        'finished_players': [],
        'loser':            None,
        'deck_size':        deck_size,
        'variant':          variant,
        'neighbors_only':   neighbors_only,
    }

def _find_first_attacker(hands: dict, trump_suit: str, deck_size: int, player_ids: list) -> int:
    best_val, best = 999, None
    for pid in player_ids:
        for card in hands.get(str(pid), []):
            r, s = parse_card(card)
            if s == trump_suit:
                v = card_value(r, deck_size)
                if v < best_val:
                    best_val, best = v, pid
    return best if best is not None else random.choice(player_ids)

# ── Moves ─────────────────────────────────────────────────────────────────────

def do_attack(state: dict, player_id: int, cards: list) -> tuple:
    """Initial attack or throw-in. Returns (new_state, error)."""
    if player_id not in get_attackers(state):
        return state, 'Сейчас не ваша очередь атаковать'
    if state['phase'] not in ('attack', 'throwing', 'defense'):
        return state, 'Неверная фаза'

    hand = list(state['hands'].get(str(player_id), []))

    # Validate cards are in hand
    for c in cards:
        if c not in hand:
            return state, f'Карты {c} нет в руке'

    # If table already has cards — can only throw matching ranks
    if state['table']:
        existing = ranks_on_table(state['table'])
        for c in cards:
            if parse_card(c)[0] not in existing:
                return state, f'{c} не подходит по достоинству'

    # Don't exceed defender's hand size
    def_hand_size = len(state['hands'].get(str(state['defender']), []))
    undefended = sum(1 for s in state['table'] if s['defense'] is None)
    if undefended + len(cards) > def_hand_size:
        return state, 'У защищающегося не хватает карт'

    s = copy.deepcopy(state)
    s['hands'][str(player_id)] = [c for c in hand if c not in cards]
    for c in cards:
        s['table'].append({'attack': c, 'defense': None})
    s['phase'] = 'defense'
    # Remove from done list if they throw more
    if player_id in s['done_attackers']:
        s['done_attackers'].remove(player_id)
    return s, None

def do_defend(state: dict, player_id: int, attack_card: str, defense_card: str) -> tuple:
    if player_id != state['defender']:
        return state, 'Вы не защищаетесь'
    if state['phase'] != 'defense':
        return state, 'Сейчас не фаза защиты'

    slot_idx = next((i for i, sl in enumerate(state['table'])
                     if sl['attack'] == attack_card and sl['defense'] is None), None)
    if slot_idx is None:
        return state, 'Такой атакующей карты нет на столе'

    hand = list(state['hands'].get(str(player_id), []))
    if defense_card not in hand:
        return state, 'Такой карты нет в руке'
    if not can_beat(attack_card, defense_card, state['trump_suit'], state['deck_size']):
        return state, 'Этой картой нельзя побить'

    s = copy.deepcopy(state)
    s['hands'][str(player_id)] = [c for c in hand if c != defense_card]
    s['table'][slot_idx]['defense'] = defense_card

    # If all cards beaten → throwing phase
    if all(sl['defense'] is not None for sl in s['table']):
        s['phase'] = 'throwing'
    return s, None

def do_transfer(state: dict, player_id: int, card: str) -> tuple:
    """Переводной: pass the attack to next player."""
    if state['variant'] != 'perevodnoj':
        return state, 'Перевод не разрешён в этом варианте'
    if player_id != state['defender']:
        return state, 'Только защищающийся может переводить'
    if state['phase'] != 'defense':
        return state, 'Неверная фаза'
    if any(sl['defense'] is not None for sl in state['table']):
        return state, 'Нельзя переводить — уже есть отбитые карты'

    rank, _ = parse_card(card)
    if rank not in {parse_card(sl['attack'])[0] for sl in state['table']}:
        return state, 'Карта не совпадает по достоинству с атакой'

    hand = list(state['hands'].get(str(player_id), []))
    if card not in hand:
        return state, 'Такой карты нет в руке'

    next_def = _next_active(state, player_id)
    if next_def is None or next_def == state['attacker']:
        return state, 'Некому переводить'

    next_def_size = len(state['hands'].get(str(next_def), []))
    if len(state['table']) + 1 > next_def_size:
        return state, 'У следующего игрока недостаточно карт'

    s = copy.deepcopy(state)
    s['hands'][str(player_id)] = [c for c in hand if c != card]
    s['table'].append({'attack': card, 'defense': None})
    s['attacker'] = player_id      # old defender now attacks
    s['defender'] = next_def
    s['done_attackers'] = []
    s['phase'] = 'defense'
    return s, None

def do_take(state: dict, player_id: int) -> tuple:
    if player_id != state['defender']:
        return state, 'Вы не защищаетесь'

    s = copy.deepcopy(state)
    hand = list(s['hands'].get(str(player_id), []))
    for sl in s['table']:
        if sl['attack']:  hand.append(sl['attack'])
        if sl['defense']: hand.append(sl['defense'])
    s['hands'][str(player_id)] = hand
    s['table'] = []
    s['done_attackers'] = []

    # Draw for everyone except taker
    s = _draw_all(s, skip=player_id)

    # Next attacker: player after defender
    new_attacker = _next_active(s, player_id)
    new_defender = _next_active(s, new_attacker) if new_attacker else None
    s['attacker'] = new_attacker
    s['defender'] = new_defender
    s['phase'] = 'attack'
    return _check_end(s), None

def do_done_attack(state: dict, player_id: int) -> tuple:
    if player_id not in get_attackers(state):
        return state, 'Вы не атакуете'
    if state['phase'] not in ('attack', 'defense', 'throwing'):
        return state, 'Неверная фаза'
    # Can't say done if there are still undefended cards
    if any(sl['defense'] is None for sl in state['table']):
        return state, 'Есть неотбитые карты — защита не завершена'

    s = copy.deepcopy(state)
    if player_id not in s['done_attackers']:
        s['done_attackers'].append(player_id)

    all_atk = get_attackers(s)
    if all(a in s['done_attackers'] for a in all_atk) or not all_atk:
        s = _end_round_success(s)
    return s, None

# ── Round end ─────────────────────────────────────────────────────────────────

def _end_round_success(state: dict) -> dict:
    s = copy.deepcopy(state)
    discard = list(s['discard'])
    for sl in s['table']:
        if sl['attack']:  discard.append(sl['attack'])
        if sl['defense']: discard.append(sl['defense'])
    s['discard'] = discard
    s['table'] = []
    s['done_attackers'] = []

    s = _draw_all(s)

    # Defender → new attacker
    new_attacker = s['defender']
    new_defender = _next_active(s, new_attacker) if new_attacker else None
    s['attacker'] = new_attacker
    s['defender'] = new_defender
    s['phase'] = 'attack'
    return _check_end(s)

def _draw_all(state: dict, skip: int = None) -> dict:
    s = copy.deepcopy(state)
    if not s['deck']:
        return _check_end(s)

    turn_order = s['turn_order']
    a_idx = turn_order.index(s['attacker']) if s['attacker'] in turn_order else 0
    draw_order = turn_order[a_idx:] + turn_order[:a_idx]

    for pid in draw_order:
        if pid == skip or pid in s['finished_players']:
            continue
        hand = list(s['hands'].get(str(pid), []))
        while len(hand) < 6 and s['deck']:
            hand.append(s['deck'].pop(0))
        s['hands'][str(pid)] = hand

    return _check_end(s)

def _check_end(state: dict) -> dict:
    s = copy.deepcopy(state)
    for pid in s['turn_order']:
        if pid in s['finished_players']:
            continue
        if not s['hands'].get(str(pid)) and not s['deck']:
            s['finished_players'].append(pid)

    act = active_players(s)
    if len(act) <= 1:
        s['phase'] = 'finished'
        s['loser'] = act[0] if act else None
    return s

# ── Public view (hides opponents' cards) ──────────────────────────────────────

def public_state(state: dict, viewer_id: int, players_meta: list) -> dict:
    """Returns state safe to send to viewer_id. Hides other players' hands."""
    meta = {p['user_id']: p for p in players_meta}
    hands_view = {}
    for pid_str, hand in state['hands'].items():
        pid = int(pid_str)
        if pid == viewer_id:
            hands_view[pid_str] = hand
        else:
            hands_view[pid_str] = len(hand)

    return {
        'deck_count':      len(state['deck']),
        'trump_suit':      state['trump_suit'],
        'trump_card':      state['trump_card'],
        'table':           state['table'],
        'turn_order':      state['turn_order'],
        'attacker':        state['attacker'],
        'defender':        state['defender'],
        'phase':           state['phase'],
        'done_attackers':  state['done_attackers'],
        'finished_players':state['finished_players'],
        'loser':           state['loser'],
        'deck_size':       state['deck_size'],
        'variant':         state['variant'],
        'neighbors_only':  state['neighbors_only'],
        'discard_count':   len(state['discard']),
        'hands':           hands_view,
        'players':         [
            {
                'user_id':      p['user_id'],
                'display_name': p['display_name'],
                'seat':         p['seat'],
                'hand_count':   len(state['hands'].get(str(p['user_id']), [])),
                'finished':     p['user_id'] in state['finished_players'],
            }
            for p in players_meta
        ],
    }
