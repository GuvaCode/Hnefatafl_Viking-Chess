unit hnefatafl_game;

interface

uses
  Raylib, SysUtils, Math, Generics.Collections;

const
  BOARD_SIZE = 11;
  CELL_SIZE = 60;
  MARGIN = 50;
  SCREEN_WIDTH = BOARD_SIZE * CELL_SIZE + 2 * MARGIN;
  SCREEN_HEIGHT = BOARD_SIZE * CELL_SIZE + 2 * MARGIN + 40;
  ANIMATION_SPEED = 3.0;

  // Piece types
  EMPTY = ' ';
  ATTACKER = 'A';
  DEFENDER = 'D';
  KING = 'K';
  THRONE = 'T';
  CORNER = 'C';

  // Game modes
  HUMAN_VS_HUMAN = 0;
  HUMAN_VS_AI = 1;
  AI_VS_HUMAN = 2;

type
  TMove = record
    FromRow, FromCol: Integer;
    ToRow, ToCol: Integer;
    Score: Integer;
  end;

  TAnimation = record
    Active: Boolean;
    FromX, FromY: Single;
    ToX, ToY: Single;
    Progress: Single;
    Piece: Char;
  end;

  TGameState = record
    Board: array[0..BOARD_SIZE-1, 0..BOARD_SIZE-1] of Char;
    AttackerTurn: Boolean;
    GameOver: Boolean;
    Winner: Char;
    SelectedRow, SelectedCol: Integer;
    Message: string;
    ShowHelp: Boolean;
    Animation: TAnimation;
    GameMode: Integer;
    Thinking: Boolean;
    LastAIMoveTime: Double;
  end;

procedure InitializeGame(var State: TGameState);
function IsValidMove(var State: TGameState; FromRow, FromCol, ToRow, ToCol: Integer): Boolean;
procedure CheckCaptures(var State: TGameState; Row, Col: Integer);
function IsGameOver(var State: TGameState): Boolean;
function MakeMove(var State: TGameState; FromRow, FromCol, ToRow, ToCol: Integer): Boolean;
procedure HandleInput(var State: TGameState);
procedure UpdateGame(var State: TGameState);
procedure DrawBoard(var State: TGameState);
procedure DrawUI(var State: TGameState);
function EvaluateBoard(var State: TGameState): Integer;
function FindBestMove(var State: TGameState): TMove;
procedure ComputerMove(var State: TGameState);
function GetAllValidMoves(var State: TGameState): Specialize TArray<TMove>;

implementation

procedure InitializeGame(var State: TGameState);
var
  i, j: Integer;
begin
  // Initialize empty board
  for i := 0 to BOARD_SIZE - 1 do
    for j := 0 to BOARD_SIZE - 1 do
      State.Board[i][j] := EMPTY;

  // Mark the corners
  State.Board[0][0] := CORNER;
  State.Board[0][BOARD_SIZE-1] := CORNER;
  State.Board[BOARD_SIZE-1][0] := CORNER;
  State.Board[BOARD_SIZE-1][BOARD_SIZE-1] := CORNER;

  // Mark the throne (center)
  State.Board[BOARD_SIZE div 2][BOARD_SIZE div 2] := THRONE;

  // Place the king
  State.Board[BOARD_SIZE div 2][BOARD_SIZE div 2] := KING;

  // Place defenders
  State.Board[BOARD_SIZE div 2-1][BOARD_SIZE div 2] := DEFENDER;
  State.Board[BOARD_SIZE div 2+1][BOARD_SIZE div 2] := DEFENDER;
  State.Board[BOARD_SIZE div 2][BOARD_SIZE div 2-1] := DEFENDER;
  State.Board[BOARD_SIZE div 2][BOARD_SIZE div 2+1] := DEFENDER;
  State.Board[BOARD_SIZE div 2-2][BOARD_SIZE div 2] := DEFENDER;
  State.Board[BOARD_SIZE div 2+2][BOARD_SIZE div 2] := DEFENDER;
  State.Board[BOARD_SIZE div 2][BOARD_SIZE div 2-2] := DEFENDER;
  State.Board[BOARD_SIZE div 2][BOARD_SIZE div 2+2] := DEFENDER;

  State.Board[4][4] := DEFENDER;
  State.Board[6][4] := DEFENDER;
  State.Board[6][6] := DEFENDER;
  State.Board[4][6] := DEFENDER;

  // Place attackers
  for i := 3 to 7 do State.Board[0][i] := ATTACKER;
  for i := 3 to 7 do State.Board[BOARD_SIZE-1][i] := ATTACKER;
  for i := 3 to 7 do State.Board[i][0] := ATTACKER;
  for i := 3 to 7 do State.Board[i][BOARD_SIZE-1] := ATTACKER;

  State.Board[5][1] := ATTACKER;
  State.Board[9][5] := ATTACKER;
  State.Board[5][9] := ATTACKER;
  State.Board[1][5] := ATTACKER;

  // Set initial game state
  State.AttackerTurn := True;
  State.GameOver := False;
  State.Winner := EMPTY;
  State.SelectedRow := -1;
  State.SelectedCol := -1;
  State.Message := 'Welcome to Hnefatafl (Viking Chess)!';
  State.ShowHelp := False;
  State.Animation.Active := False;
  State.GameMode := HUMAN_VS_AI;
  State.Thinking := False;
  State.LastAIMoveTime := 0;
end;

function IsValidMove(var State: TGameState; FromRow, FromCol, ToRow, ToCol: Integer): Boolean;
var
  i, Start, End_: Integer;
  Piece: Char;
begin
  Result := False;

  // Check if coordinates are within the board
  if (FromRow < 0) or (FromRow >= BOARD_SIZE) or (FromCol < 0) or (FromCol >= BOARD_SIZE) or
     (ToRow < 0) or (ToRow >= BOARD_SIZE) or (ToCol < 0) or (ToCol >= BOARD_SIZE) then
    Exit;

  // Check if there is a piece at the starting position
  Piece := State.Board[FromRow][FromCol];
  if (Piece = EMPTY) or (Piece = CORNER) or (Piece = THRONE) then
    Exit;

  // Check if the piece belongs to the current player
  if (State.AttackerTurn and (Piece <> ATTACKER)) or
     (not State.AttackerTurn and (Piece <> DEFENDER) and (Piece <> KING)) then
    Exit;

  // Check if the destination is empty or is a corner (only the king can go to corners)
  if (State.Board[ToRow][ToCol] <> EMPTY) and
     not ((Piece = KING) and (State.Board[ToRow][ToCol] = CORNER)) then
    Exit;

  // Special rule: only the king can enter the throne and corners
  if (State.Board[ToRow][ToCol] = THRONE) and (Piece <> KING) then
    Exit;

  // Check if the move is either horizontal or vertical
  if (FromRow <> ToRow) and (FromCol <> ToCol) then
    Exit;

  // Check if the path is clear
  if FromRow = ToRow then
  begin
    // Horizontal move
    if FromCol < ToCol then
    begin
      Start := FromCol + 1;
      End_ := ToCol;
    end
    else
    begin
      Start := ToCol + 1;
      End_ := FromCol;
    end;

    for i := Start to End_ - 1 do
    begin
      if (State.Board[FromRow][i] <> EMPTY) and
         not ((State.Board[FromRow][i] = THRONE) and (State.Board[BOARD_SIZE div 2][BOARD_SIZE div 2] <> KING)) then
        Exit;
    end;
  end
  else
  begin
    // Vertical move
    if FromRow < ToRow then
    begin
      Start := FromRow + 1;
      End_ := ToRow;
    end
    else
    begin
      Start := ToRow + 1;
      End_ := FromRow;
    end;

    for i := Start to End_ - 1 do
    begin
      if (State.Board[i][FromCol] <> EMPTY) and
         not ((State.Board[i][FromCol] = THRONE) and (State.Board[BOARD_SIZE div 2][BOARD_SIZE div 2] <> KING)) then
        Exit;
    end;
  end;

  Result := True;
end;

procedure CheckCaptures(var State: TGameState; Row, Col: Integer);
var
  CurrentPlayer, Opponent: Char;
  Dir, CaptureRow, CaptureCol, SandwichRow, SandwichCol: Integer;
  KingDir, AdjacentRow, AdjacentCol, KingCaptureCount: Integer;
  AgainstThrone, AgainstCorner: Boolean;
  CapturePiece: Char;
  KingRow, KingCol: Integer;
begin
  if State.AttackerTurn then
  begin
    CurrentPlayer := ATTACKER;
    Opponent := DEFENDER;
  end
  else
  begin
    CurrentPlayer := DEFENDER;
    Opponent := ATTACKER;
  end;

  // Check for regular captures first
  for Dir := 0 to 3 do
  begin
    case Dir of
      0: begin CaptureRow := Row - 1; CaptureCol := Col; end;
      1: begin CaptureRow := Row; CaptureCol := Col + 1; end;
      2: begin CaptureRow := Row + 1; CaptureCol := Col; end;
      3: begin CaptureRow := Row; CaptureCol := Col - 1; end;
    end;

    if (CaptureRow >= 0) and (CaptureRow < BOARD_SIZE) and
       (CaptureCol >= 0) and (CaptureCol < BOARD_SIZE) then
    begin
      CapturePiece := State.Board[CaptureRow][CaptureCol];

      // Check if the piece belongs to opponent
      if ((Opponent = DEFENDER) and ((CapturePiece = DEFENDER) or (CapturePiece = KING))) or
         ((Opponent = ATTACKER) and (CapturePiece = ATTACKER)) then
      begin
        case Dir of
          0: begin SandwichRow := CaptureRow - 1; SandwichCol := CaptureCol; end;
          1: begin SandwichRow := CaptureRow; SandwichCol := CaptureCol + 1; end;
          2: begin SandwichRow := CaptureRow + 1; SandwichCol := CaptureCol; end;
          3: begin SandwichRow := CaptureRow; SandwichCol := CaptureCol - 1; end;
        end;

        // Check if sandwiching position is valid
        if (SandwichRow >= 0) and (SandwichRow < BOARD_SIZE) and
           (SandwichCol >= 0) and (SandwichCol < BOARD_SIZE) then
        begin
          // King capture requires special handling
          if CapturePiece = KING then
          begin
            KingRow := CaptureRow;
            KingCol := CaptureCol;
            KingCaptureCount := 0;
            AgainstThrone := False;
            AgainstCorner := False;

            // Check all four directions around the king
            for KingDir := 0 to 3 do
            begin
              case KingDir of
                0: begin AdjacentRow := KingRow - 1; AdjacentCol := KingCol; end;
                1: begin AdjacentRow := KingRow; AdjacentCol := KingCol + 1; end;
                2: begin AdjacentRow := KingRow + 1; AdjacentCol := KingCol; end;
                3: begin AdjacentRow := KingRow; AdjacentCol := KingCol - 1; end;
              end;

              if (AdjacentRow >= 0) and (AdjacentRow < BOARD_SIZE) and
                 (AdjacentCol >= 0) and (AdjacentCol < BOARD_SIZE) then
              begin
                if State.Board[AdjacentRow][AdjacentCol] = ATTACKER then
                  Inc(KingCaptureCount)
                else if State.Board[AdjacentRow][AdjacentCol] = THRONE then
                begin
                  AgainstThrone := True;
                  Inc(KingCaptureCount);
                end
                else if State.Board[AdjacentRow][AdjacentCol] = CORNER then
                begin
                  AgainstCorner := True;
                  Inc(KingCaptureCount);
                end;
              end
              else
              begin
                // Edge of board counts as attacker for king capture
                Inc(KingCaptureCount);
              end;
            end;

            // King is captured if:
            // 1. Surrounded by 4 attackers (or edges/throne/corners)
            // 2. On throne and surrounded by 3 attackers (with throne as 4th)
            if (KingCaptureCount >= 4) or
               (AgainstThrone and (KingCaptureCount >= 3)) or
               (AgainstCorner and (KingCaptureCount >= 3)) then
            begin
              State.Board[KingRow][KingCol] := EMPTY;
              State.GameOver := True;
              State.Winner := ATTACKER;
              State.Message := 'King captured! Attackers win!';
              Exit;
            end;
          end
          else
          begin
            // Regular piece capture
            // Allow capture if sandwiching piece is:
            // - Current player's piece
            // - Corner (except when capturing king)
            // - Throne (except when capturing king)
            // - King (only for defenders capturing attackers)
            if (State.Board[SandwichRow][SandwichCol] = CurrentPlayer) or
               (State.Board[SandwichRow][SandwichCol] = CORNER) or
               (State.Board[SandwichRow][SandwichCol] = THRONE) or
               (not State.AttackerTurn and (State.Board[SandwichRow][SandwichCol] = KING)) then
            begin
              State.Board[CaptureRow][CaptureCol] := EMPTY;
              State.Message := 'Piece captured!';
            end;
          end;
        end;
      end;
    end;
  end;
end;

function IsGameOver(var State: TGameState): Boolean;
var
  i, j: Integer;
  KingFound, AttackersFound, DefendersFound: Boolean;
begin
  Result := False;
  KingFound := False;
  AttackersFound := False;
  DefendersFound := False;

  for i := 0 to BOARD_SIZE - 1 do
  begin
    for j := 0 to BOARD_SIZE - 1 do
    begin
      if State.Board[i][j] = KING then
      begin
        KingFound := True;

        if ((i = 0) and (j = 0)) or
           ((i = 0) and (j = BOARD_SIZE-1)) or
           ((i = BOARD_SIZE-1) and (j = 0)) or
           ((i = BOARD_SIZE-1) and (j = BOARD_SIZE-1)) then
        begin
          State.Winner := DEFENDER;
          State.Message := 'King escaped! Defenders win!';
          Exit(True);
        end;
      end
      else if State.Board[i][j] = ATTACKER then
        AttackersFound := True
      else if State.Board[i][j] = DEFENDER then
        DefendersFound := True;
    end;
  end;

  if not KingFound then
  begin
    State.Winner := ATTACKER;
    State.Message := 'King captured! Attackers win!';
    Exit(True);
  end;

  if not AttackersFound then
  begin
    State.Winner := DEFENDER;
    State.Message := 'All attackers captured! Defenders win!';
    Exit(True);
  end;

  if not DefendersFound then
  begin
    i := BOARD_SIZE div 2;
    j := BOARD_SIZE div 2;
    if (State.Board[i][j] = KING) then
    begin
      if ((i > 0) and (State.Board[i-1][j] = ATTACKER)) and
         ((j < BOARD_SIZE-1) and (State.Board[i][j+1] = ATTACKER)) and
         ((i < BOARD_SIZE-1) and (State.Board[i+1][j] = ATTACKER)) and
         ((j > 0) and (State.Board[i][j-1] = ATTACKER)) then
      begin
        State.Winner := ATTACKER;
        State.Message := 'King surrounded! Attackers win!';
        Exit(True);
      end;
    end;
  end;
end;

function MakeMove(var State: TGameState; FromRow, FromCol, ToRow, ToCol: Integer): Boolean;
begin
  Result := False;

  if not IsValidMove(State, FromRow, FromCol, ToRow, ToCol) then
    Exit;

  // Start animation
  State.Animation.Active := True;
  State.Animation.FromX := FromCol;
  State.Animation.FromY := FromRow;
  State.Animation.ToX := ToCol;
  State.Animation.ToY := ToRow;
  State.Animation.Progress := 0.0;
  State.Animation.Piece := State.Board[FromRow][FromCol];

  Result := True;
end;

procedure UpdateGame(var State: TGameState);
begin
  if State.Animation.Active then
  begin
    State.Animation.Progress := State.Animation.Progress + ANIMATION_SPEED * GetFrameTime();
    if State.Animation.Progress >= 1.0 then
    begin
      // After animation completes, move the piece
      State.Board[Trunc(State.Animation.ToY)][Trunc(State.Animation.ToX)] := State.Animation.Piece;

      // Clear the original position (if not throne)
      if (Trunc(State.Animation.FromY) = BOARD_SIZE div 2) and
         (Trunc(State.Animation.FromX) = BOARD_SIZE div 2) then
        State.Board[Trunc(State.Animation.FromY)][Trunc(State.Animation.FromX)] := THRONE
      else
        State.Board[Trunc(State.Animation.FromY)][Trunc(State.Animation.FromX)] := EMPTY;

      // Check captures after the real move
      CheckCaptures(State, Trunc(State.Animation.ToY), Trunc(State.Animation.ToX));

      // Check if game is over
      if IsGameOver(State) then
        State.GameOver := True
      else
        State.AttackerTurn := not State.AttackerTurn;

      State.SelectedRow := -1;
      State.SelectedCol := -1;
      State.Animation.Active := False;
    end;
  end;
end;

function GetAllValidMoves(var State: TGameState): specialize TArray<TMove>;
var
  i, j, Dir, Steps, NewRow, NewCol: Integer;
  CurrentPiece: Char;
  Move: TMove;
  Dirs: array[0..3] of TVector2 = ((x:0; y:-1), (x:1; y:0), (x:0; y:1), (x:-1; y:0));
  MoveList: specialize TList<TMove>;
begin
  MoveList := specialize TList<TMove>.Create;
  try
    // Iterate through all pieces
    for i := 0 to BOARD_SIZE - 1 do
    begin
      for j := 0 to BOARD_SIZE - 1 do
      begin
        CurrentPiece := State.Board[i][j];

        // Check if piece belongs to current player
        if (State.AttackerTurn and (CurrentPiece = ATTACKER)) or
           (not State.AttackerTurn and ((CurrentPiece = DEFENDER) or (CurrentPiece = KING))) then
        begin
          // Check all possible directions
          for Dir := 0 to 3 do
          begin
            Steps := 1;
            while True do
            begin
              NewRow := i + Trunc(Dirs[Dir].y * Steps);
              NewCol := j + Trunc(Dirs[Dir].x * Steps);

              // Check if move is valid
              if not IsValidMove(State, i, j, NewRow, NewCol) then
                Break;

              // Add valid move to list
              Move.FromRow := i;
              Move.FromCol := j;
              Move.ToRow := NewRow;
              Move.ToCol := NewCol;
              Move.Score := 0; // Will be evaluated later
              MoveList.Add(Move);

              Inc(Steps);
            end;
          end;
        end;
      end;
    end;

    Result := MoveList.ToArray;
  finally
    MoveList.Free;
  end;
end;

function EvaluateBoard(var State: TGameState): Integer;
var
  i, j, KingRow, KingCol: Integer;
  AttackerCount, DefenderCount: Integer;
  KingDistanceToCorner, KingDistanceToCenter: Integer;
  AttackersNearKing, DefendersNearKing: Integer;
  DefenderEscapePaths: Integer;
begin
  Result := 0;
  AttackerCount := 0;
  DefenderCount := 0;
  KingRow := -1;
  KingCol := -1;
  AttackersNearKing := 0;
  DefendersNearKing := 0;
  DefenderEscapePaths := 0;

  // Подсчет фигур и определение позиции короля
  for i := 0 to BOARD_SIZE - 1 do
  begin
    for j := 0 to BOARD_SIZE - 1 do
    begin
      case State.Board[i][j] of
        ATTACKER:
          begin
            Inc(AttackerCount);
            if (KingRow <> -1) and (Abs(i - KingRow) <= 2) and (Abs(j - KingCol) <= 2) then
              Inc(AttackersNearKing);
          end;
        DEFENDER, KING:
          begin
            Inc(DefenderCount);
            if State.Board[i][j] = KING then
            begin
              KingRow := i;
              KingCol := j;
            end
            else if (KingRow <> -1) and (Abs(i - KingRow) <= 1) and (Abs(j - KingCol) <= 1) then
              Inc(DefendersNearKing);
          end;
      end;
    end;
  end;

  // Оценка позиции короля
  if KingRow <> -1 then
  begin
    // Победа защитников - король в углу
    if ((KingRow = 0) and (KingCol = 0)) or
       ((KingRow = 0) and (KingCol = BOARD_SIZE-1)) or
       ((KingRow = BOARD_SIZE-1) and (KingCol = 0)) or
       ((KingRow = BOARD_SIZE-1) and (KingCol = BOARD_SIZE-1)) then
    begin
      if State.AttackerTurn then
        Result := -100000
      else
        Result := 100000;
      Exit;
    end;

    // Расчет расстояний
    KingDistanceToCorner := Min(
      Min(KingRow + KingCol, KingRow + (BOARD_SIZE-1 - KingCol)),
      Min((BOARD_SIZE-1 - KingRow) + KingCol, (BOARD_SIZE-1 - KingRow) + (BOARD_SIZE-1 - KingCol))
    );

    KingDistanceToCenter := Abs(KingRow - BOARD_SIZE div 2) + Abs(KingCol - BOARD_SIZE div 2);

    // Оценка для защитников
    if not State.AttackerTurn then
    begin
      // Большой бонус за приближение к углу
      Result := Result - KingDistanceToCorner * 50;

      // Бонус за свободные пути к углам
      if KingRow = 0 then Inc(DefenderEscapePaths);
      if KingRow = BOARD_SIZE-1 then Inc(DefenderEscapePaths);
      if KingCol = 0 then Inc(DefenderEscapePaths);
      if KingCol = BOARD_SIZE-1 then Inc(DefenderEscapePaths);

      Result := Result - DefenderEscapePaths * 30;
    end
    else // Оценка для атакующих
    begin
      // Бонус за приближение короля к центру
      Result := Result + KingDistanceToCenter * 20;

      // Бонус за атакующих рядом с королем
      Result := Result + AttackersNearKing * 15;

      // Штраф за защитников рядом с королем
      Result := Result - DefendersNearKing * 20;
    end;
  end;

  // Оценка количества фигур
  if State.AttackerTurn then
    Result := Result + (AttackerCount - DefenderCount) * 10
  else
    Result := Result + (DefenderCount - AttackerCount) * 10;
end;

function FindBestMove(var State: TGameState): TMove;
var
  i, j, k, OldDist, NewDist: Integer;
  TestState: TGameState;
  MoveList: specialize TArray<TMove>;
  BestScore: Integer;
  KingRow, KingCol: Integer;
  CurrentScore: Integer;
begin
  // Поиск позиции короля
  KingRow := -1;
  KingCol := -1;
  for i := 0 to BOARD_SIZE - 1 do
    for j := 0 to BOARD_SIZE - 1 do
      if State.Board[i][j] = KING then
      begin
        KingRow := i;
        KingCol := j;
        Break;
      end;

  // Получение всех возможных ходов
  MoveList := GetAllValidMoves(State);

  if Length(MoveList) = 0 then
  begin
    Result.FromRow := -1;
    Result.FromCol := -1;
    Result.ToRow := -1;
    Result.ToCol := -1;
    Result.Score := -MaxInt;
    Exit;
  end;

  // Оценка каждого хода
  for i := 0 to High(MoveList) do
  begin
    // Копирование состояния для тестирования хода
    TestState := State;
    TestState.Board[MoveList[i].ToRow][MoveList[i].ToCol] :=
      TestState.Board[MoveList[i].FromRow][MoveList[i].FromCol];
    TestState.Board[MoveList[i].FromRow][MoveList[i].FromCol] := EMPTY;

    // Проверка захватов после хода
    CheckCaptures(TestState, MoveList[i].ToRow, MoveList[i].ToCol);

    // Базовая оценка позиции
    CurrentScore := EvaluateBoard(TestState);

    // Специальные бонусы для защитников
    if not State.AttackerTurn then
    begin
      // Ход королем
      if State.Board[MoveList[i].FromRow][MoveList[i].FromCol] = KING then
      begin
        // Большой бонус за движение к углам
         OldDist := Min(
          Min(MoveList[i].FromRow + MoveList[i].FromCol,
              MoveList[i].FromRow + (BOARD_SIZE-1 - MoveList[i].FromCol)),
          Min((BOARD_SIZE-1 - MoveList[i].FromRow) + MoveList[i].FromCol,
              (BOARD_SIZE-1 - MoveList[i].FromRow) + (BOARD_SIZE-1 - MoveList[i].FromCol)));

        NewDist := Min(
          Min(MoveList[i].ToRow + MoveList[i].ToCol,
              MoveList[i].ToRow + (BOARD_SIZE-1 - MoveList[i].ToCol)),
          Min((BOARD_SIZE-1 - MoveList[i].ToRow) + MoveList[i].ToCol,
              (BOARD_SIZE-1 - MoveList[i].ToRow) + (BOARD_SIZE-1 - MoveList[i].ToCol)));

        if NewDist < OldDist then
          Inc(CurrentScore, 100); // Очень большой бонус

        // Дополнительный бонус за выход на край доски
        if (MoveList[i].ToRow = 0) or (MoveList[i].ToRow = BOARD_SIZE-1) or
           (MoveList[i].ToCol = 0) or (MoveList[i].ToCol = BOARD_SIZE-1) then
          Inc(CurrentScore, 50);
      end
      else
      begin
        // Бонус за защитников, расчищающих путь королю
        if (KingRow <> -1) and
           ((MoveList[i].ToRow = KingRow) or (MoveList[i].ToCol = KingCol)) then
          Inc(CurrentScore, 30);
      end;
    end
    else // Специальные бонусы для атакующих
    begin
      // Бонус за приближение к королю
      if KingRow <> -1 then
      begin
        OldDist := Abs(MoveList[i].FromRow - KingRow) + Abs(MoveList[i].FromCol - KingCol);
        NewDist := Abs(MoveList[i].ToRow - KingRow) + Abs(MoveList[i].ToCol - KingCol);

        if NewDist < OldDist then
          Inc(CurrentScore, 40);

        // Большой бонус за занятие позиции рядом с королем
        if NewDist <= 1 then
          Inc(CurrentScore, 60);
      end;

      // Бонус за блокировку защитников
      for j := 0 to BOARD_SIZE - 1 do
        for k := 0 to BOARD_SIZE - 1 do
          if State.Board[j][k] = DEFENDER then
          begin
            if (Abs(MoveList[i].ToRow - j) = 1) and (MoveList[i].ToCol = k) or
               (Abs(MoveList[i].ToCol - k) = 1) and (MoveList[i].ToRow = j) then
              Inc(CurrentScore, 20);
          end;
    end;

    // Учет завершения игры
    if TestState.GameOver then
    begin
      if TestState.Winner = ATTACKER then
        CurrentScore := 100000
      else
        CurrentScore := -100000;
    end;

    MoveList[i].Score := CurrentScore;
  end;

  // Выбор лучшего хода
  Result := MoveList[0];
  BestScore := MoveList[0].Score;

  for i := 1 to High(MoveList) do
    if MoveList[i].Score > BestScore then
    begin
      BestScore := MoveList[i].Score;
      Result := MoveList[i];
    end;
end;

procedure ComputerMove(var State: TGameState);
var
  BestMove: TMove;
begin
  // Add delay to make computer move visible
  if (GetTime() - State.LastAIMoveTime) < 0.5 then
    Exit;

  State.Thinking := True;
  State.LastAIMoveTime := GetTime();

  // Find the best move
  BestMove := FindBestMove(State);

  // Apply the best move
  if (BestMove.FromRow <> -1) and (BestMove.FromCol <> -1) then
  begin
    MakeMove(State, BestMove.FromRow, BestMove.FromCol, BestMove.ToRow, BestMove.ToCol);
    State.Message := 'Computer made a move';
  end;

  State.Thinking := False;
end;

procedure HandleInput(var State: TGameState);
var
  MousePos: TVector2;
  Row, Col, i, j, NewRow, NewCol: Integer;
  CanMove: Boolean;
  Dirs: array[0..3] of TVector2 = ((x:0; y:-1), (x:1; y:0), (x:0; y:1), (x:-1; y:0));
  CurrentPiece, ClickedPiece: Char;
begin
  if IsKeyPressed(KEY_H) then
    State.ShowHelp := not State.ShowHelp;

  if IsKeyPressed(KEY_R) then
    InitializeGame(State);

  if IsKeyPressed(KEY_ONE) then
    State.GameMode := HUMAN_VS_HUMAN;

  if IsKeyPressed(KEY_TWO) then
    State.GameMode := HUMAN_VS_AI;

  if IsKeyPressed(KEY_THREE) then
    State.GameMode := AI_VS_HUMAN;

  if State.ShowHelp then
  begin
    if IsMouseButtonPressed(MOUSE_LEFT_BUTTON) then
      State.ShowHelp := False;
    Exit;
  end;

  if State.GameOver then
  begin
    if IsMouseButtonPressed(MOUSE_LEFT_BUTTON) or IsKeyPressed(KEY_SPACE) then
      InitializeGame(State);
    Exit;
  end;

  // Don't handle input during animation or when computer is thinking
  if State.Animation.Active or State.Thinking then
    Exit;

  // Computer's turn in HUMAN_VS_AI or AI_VS_HUMAN modes
  if ((State.GameMode = HUMAN_VS_AI) and State.AttackerTurn) or
     ((State.GameMode = AI_VS_HUMAN) and not State.AttackerTurn) then
  begin
    ComputerMove(State);
    Exit;
  end;

  if IsMouseButtonPressed(MOUSE_LEFT_BUTTON) then
  begin
    MousePos := GetMousePosition();

    if (MousePos.X >= MARGIN) and (MousePos.X < MARGIN + BOARD_SIZE * CELL_SIZE) and
       (MousePos.Y >= MARGIN) and (MousePos.Y < MARGIN + BOARD_SIZE * CELL_SIZE) then
    begin
      Col := Trunc((MousePos.X - MARGIN) / CELL_SIZE);
      Row := Trunc((MousePos.Y - MARGIN) / CELL_SIZE);
      ClickedPiece := State.Board[Row][Col];

      if State.AttackerTurn then
        CurrentPiece := ATTACKER
      else
        CurrentPiece := DEFENDER;

      if (State.SelectedRow <> -1) and (State.SelectedCol <> -1) then
      begin
        if (Row = State.SelectedRow) and (Col = State.SelectedCol) then
        begin
          State.SelectedRow := -1;
          State.SelectedCol := -1;
          State.Message := 'Selection canceled.';
        end
        else if ((ClickedPiece = CurrentPiece) or
                (ClickedPiece = KING) and not State.AttackerTurn) then
        begin
          CanMove := False;
          for i := 0 to 3 do
          begin
            j := 1;
            while True do
            begin
              NewRow := Row + Trunc(Dirs[i].y * j);
              NewCol := Col + Trunc(Dirs[i].x * j);

              if (NewRow < 0) or (NewRow >= BOARD_SIZE) or
                 (NewCol < 0) or (NewCol >= BOARD_SIZE) then
                Break;

              if (State.Board[NewRow][NewCol] <> EMPTY) and
                 not ((State.Board[NewRow][NewCol] = THRONE) and (ClickedPiece = KING)) and
                 not ((State.Board[NewRow][NewCol] = CORNER) and (ClickedPiece = KING)) then
                Break;

              if IsValidMove(State, Row, Col, NewRow, NewCol) then
              begin
                CanMove := True;
                Break;
              end;

              Inc(j);
            end;

            if CanMove then Break;
          end;

          if CanMove then
          begin
            State.SelectedRow := Row;
            State.SelectedCol := Col;
            State.Message := 'New piece selected. Choose destination.';
          end
          else
          begin
            State.Message := 'This piece cannot move. Select another.';
          end;
        end
        else
        begin
          if MakeMove(State, State.SelectedRow, State.SelectedCol, Row, Col) then
            State.Message := 'Move successful.'
          else
            State.Message := 'Invalid move. Try again.';
        end;
      end
      else
      begin
        if ((State.AttackerTurn and (ClickedPiece = ATTACKER)) or
           (not State.AttackerTurn and ((ClickedPiece = DEFENDER) or (ClickedPiece = KING)))) then
        begin
          CanMove := False;
          for i := 0 to 3 do
          begin
            j := 1;
            while True do
            begin
              NewRow := Row + Trunc(Dirs[i].y * j);
              NewCol := Col + Trunc(Dirs[i].x * j);

              if (NewRow < 0) or (NewRow >= BOARD_SIZE) or
                 (NewCol < 0) or (NewCol >= BOARD_SIZE) then
                Break;

              if (State.Board[NewRow][NewCol] <> EMPTY) and
                 not ((State.Board[NewRow][NewCol] = THRONE) and (ClickedPiece = KING)) and
                 not ((State.Board[NewRow][NewCol] = CORNER) and (ClickedPiece = KING)) then
                Break;

              if IsValidMove(State, Row, Col, NewRow, NewCol) then
              begin
                CanMove := True;
                Break;
              end;

              Inc(j);
            end;

            if CanMove then Break;
          end;

          if CanMove then
          begin
            State.SelectedRow := Row;
            State.SelectedCol := Col;
            State.Message := 'Piece selected. Choose destination.';
          end
          else
          begin
            State.Message := 'This piece cannot move. Select another.';
          end;
        end
        else
        begin
          State.Message := 'Select one of your pieces.';
        end;
      end;
    end;
  end;
end;

procedure DrawBoard(var State: TGameState);
var
  i, j, X, Y: Integer;
  Piece: Char;
  AnimX, AnimY: Single;
  ABC: String;
  Dirs: array[0..3] of TVector2 = ((X:0; Y:-1), (X:1; Y:0), (X:0; Y:1), (X:-1; Y:0));
  Dir, Steps, NewRow, NewCol: Integer;
begin
  // Draw board cells
  for i := 0 to BOARD_SIZE - 1 do
  begin
    for j := 0 to BOARD_SIZE - 1 do
    begin
      X := MARGIN + j * CELL_SIZE;
      Y := MARGIN + i * CELL_SIZE;

      // Draw cell background
      if (i = State.SelectedRow) and (j = State.SelectedCol) then
        DrawRectangle(X, Y, CELL_SIZE, CELL_SIZE, ColorCreate(200, 200, 100, 255))
      else if (i + j) mod 2 = 0 then
        DrawRectangle(X, Y, CELL_SIZE, CELL_SIZE, ColorCreate(210, 180, 140, 255))
      else
        DrawRectangle(X, Y, CELL_SIZE, CELL_SIZE, ColorCreate(139, 69, 19, 255));

      DrawRectangleLines(X, Y, CELL_SIZE, CELL_SIZE, BLACK);

      // Draw special squares
      if (i = BOARD_SIZE div 2) and (j = BOARD_SIZE div 2) then
      begin
        if State.Board[i][j] = THRONE then
          DrawCircle(X + CELL_SIZE div 2, Y + CELL_SIZE div 2, CELL_SIZE div 3, GOLD)
        else if State.Board[i][j] <> KING then
          DrawCircle(X + CELL_SIZE div 2, Y + CELL_SIZE div 2, CELL_SIZE div 3, ColorCreate(255, 215, 0, 100));
      end
      else if ((i = 0) and (j = 0)) or
              ((i = 0) and (j = BOARD_SIZE-1)) or
              ((i = BOARD_SIZE-1) and (j = 0)) or
              ((i = BOARD_SIZE-1) and (j = BOARD_SIZE-1)) then
      begin
        DrawCircle(X + CELL_SIZE div 2, Y + CELL_SIZE div 2, CELL_SIZE div 3, GRAY);
      end;
    end;
  end;

  // Draw possible moves if piece is selected
  if (State.SelectedRow <> -1) and (State.SelectedCol <> -1) then
  begin
    Piece := State.Board[State.SelectedRow][State.SelectedCol];

    // Check if selected piece belongs to current player
    if (State.AttackerTurn and (Piece = ATTACKER)) or
       (not State.AttackerTurn and ((Piece = DEFENDER) or (Piece = KING))) then
    begin
      // Check all possible directions
      for Dir := 0 to 3 do
      begin
        Steps := 1;
        while True do
        begin
          NewRow := Trunc(State.SelectedRow + Dirs[Dir].Y * Steps);
          NewCol := TRunc(State.SelectedCol + Dirs[Dir].X * Steps);

          // Check if move is valid
          if not IsValidMove(State, State.SelectedRow, State.SelectedCol, NewRow, NewCol) then
            Break;

          // Draw possible move indicator
          X := MARGIN + NewCol * CELL_SIZE;
          Y := MARGIN + NewRow * CELL_SIZE;
          DrawCircle(X + CELL_SIZE div 2, Y + CELL_SIZE div 2, 10,
            ColorCreate(0, 255, 0, 150)); // Green semi-transparent circle

          Inc(Steps);
        end;
      end;
    end;
  end;

  // Draw all pieces except the animated one (if any)
  for i := 0 to BOARD_SIZE - 1 do
  begin
    for j := 0 to BOARD_SIZE - 1 do
    begin
      // Skip animated piece
      if State.Animation.Active and
         (i = Trunc(State.Animation.FromY)) and (j = Trunc(State.Animation.FromX)) then
        Continue;

      X := MARGIN + j * CELL_SIZE;
      Y := MARGIN + i * CELL_SIZE;
      Piece := State.Board[i][j];

      case Piece of
        KING:
          begin
            DrawCircle(X + CELL_SIZE div 2, Y + CELL_SIZE div 2, CELL_SIZE div 3 - 5, GOLD);
            DrawText('K', X + CELL_SIZE div 2 - 8, Y + CELL_SIZE div 2 - 10, 20, BLACK);
          end;
        DEFENDER:
          begin
            DrawCircle(X + CELL_SIZE div 2, Y + CELL_SIZE div 2, CELL_SIZE div 3 - 5, BLUE);
            DrawText('D', X + CELL_SIZE div 2 - 8, Y + CELL_SIZE div 2 - 10, 20, WHITE);
          end;
        ATTACKER:
          begin
            DrawCircle(X + CELL_SIZE div 2, Y + CELL_SIZE div 2, CELL_SIZE div 3 - 5, RED);
            DrawText('A', X + CELL_SIZE div 2 - 8, Y + CELL_SIZE div 2 - 10, 20, WHITE);
          end;
      end;
    end;
  end;

  // Draw animated piece on top of others
  if State.Animation.Active then
  begin
    AnimX := MARGIN + (State.Animation.FromX + (State.Animation.ToX - State.Animation.FromX) * State.Animation.Progress) * CELL_SIZE;
    AnimY := MARGIN + (State.Animation.FromY + (State.Animation.ToY - State.Animation.FromY) * State.Animation.Progress) * CELL_SIZE;

    case State.Animation.Piece of
      KING:
        begin
          DrawCircle(Trunc(AnimX + CELL_SIZE div 2), Trunc(AnimY + CELL_SIZE div 2), CELL_SIZE div 3 - 5, GOLD);
          DrawText('K', Trunc(AnimX + CELL_SIZE div 2 - 8), Trunc(AnimY + CELL_SIZE div 2 - 10), 20, BLACK);
        end;
      DEFENDER:
        begin
          DrawCircle(Trunc(AnimX + CELL_SIZE div 2), Trunc(AnimY + CELL_SIZE div 2), CELL_SIZE div 3 - 5, BLUE);
          DrawText('D', Trunc(AnimX + CELL_SIZE div 2 - 8), Trunc(AnimY + CELL_SIZE div 2 - 10), 20, WHITE);
        end;
      ATTACKER:
        begin
          DrawCircle(Trunc(AnimX + CELL_SIZE div 2), Trunc(AnimY + CELL_SIZE div 2), CELL_SIZE div 3 - 5, RED);
          DrawText('A', Trunc(AnimX + CELL_SIZE div 2 - 8), Trunc(AnimY + CELL_SIZE div 2 - 10), 20, WHITE);
        end;
    end;
  end;

  // Draw coordinates
  for i := 0 to BOARD_SIZE - 1 do
  begin
    // Column letters at top and bottom
    Abc := Chr(Ord('A') + i);
    DrawText(PChar(Abc), MARGIN + i * CELL_SIZE + CELL_SIZE div 2 - 5, MARGIN - 25, 20, BLACK);
    DrawText(PChar(Abc), MARGIN + i * CELL_SIZE + CELL_SIZE div 2 - 5, MARGIN + BOARD_SIZE * CELL_SIZE + 5, 20, BLACK);

    // Row numbers on left and right
    DrawText(PChar(IntToStr(i + 1)), MARGIN - 25, MARGIN + i * CELL_SIZE + CELL_SIZE div 2 - 10, 20, BLACK);
    DrawText(PChar(IntToStr(i + 1)), MARGIN + BOARD_SIZE * CELL_SIZE + 5, MARGIN + i * CELL_SIZE + CELL_SIZE div 2 - 10, 20, BLACK);
  end;
end;

procedure DrawUI(var State: TGameState);
var
  TurnText, ModeText: string;
  YPos: Integer;
begin
  YPos := MARGIN + BOARD_SIZE * CELL_SIZE + 20;

  if State.GameOver then
  begin
    if State.Winner = ATTACKER then
      TurnText := 'Game Over - Attackers Win!'
    else
      TurnText := 'Game Over - Defenders Win!';
  end
  else
  begin
    if State.AttackerTurn then
      TurnText := 'Attackers Turn (Red)'
    else
      TurnText := 'Defenders Turn (Blue)';
  end;

  case State.GameMode of
    HUMAN_VS_HUMAN: ModeText := 'Mode: Human vs Human (1)';
    HUMAN_VS_AI: ModeText := 'Mode: Human vs AI (2)';
    AI_VS_HUMAN: ModeText := 'Mode: AI vs Human (3)';
  end;

  DrawText(PChar(ModeText), SCREEN_WIDTH - 150, 10, 10, BLACK);

  if State.Thinking then
    DrawText('Computer is thinking...', MARGIN, YPos, 10, BLACK)
  else
    DrawText(PChar(TurnText), MARGIN, YPos + 10, 10, BLACK);

  DrawText(PChar(State.Message), MARGIN, YPos + 20, 10, BLACK);

  DrawText('Click to select, click destination to move', MARGIN, YPos + 35, 10, DARKGRAY);
  DrawText('Press H for help, R to restart, 1-3 to change mode', MARGIN, YPos + 45, 10, DARKGRAY);

  if State.ShowHelp then
  begin
    DrawRectangle(MARGIN, MARGIN, BOARD_SIZE * CELL_SIZE , BOARD_SIZE * CELL_SIZE , ColorCreate(240, 240, 240, 240));
    DrawRectangleLines(MARGIN, MARGIN, BOARD_SIZE * CELL_SIZE , BOARD_SIZE * CELL_SIZE , DARKGRAY);

    DrawText('Hnefatafl Rules:', MARGIN + 20  , MARGIN + 10 , 20, BLACK);
    DrawText('- Attackers (Red A) move first and try to capture the King', MARGIN + 20, MARGIN + 50, 10, BLACK);
    DrawText('- Defenders (Blue D) help the King (Gold K) escape to a corner', MARGIN + 20, MARGIN + 80, 10, BLACK);
    DrawText('- All pieces move like rooks in chess (horizontally/vertically)', MARGIN + 20, MARGIN + 110, 10, BLACK);
    DrawText('- Capture by sandwiching opponent pieces between two of yours', MARGIN + 20, MARGIN + 140, 10, BLACK);
    DrawText('- King needs to be surrounded on 4 sides to be captured', MARGIN + 20, MARGIN + 170, 10, BLACK);
    DrawText('- Central square is the throne (⊕), corners are escape points (⊡)', MARGIN + 20, MARGIN + 200, 10, BLACK);
    DrawText('Click anywhere or press H to close help', MARGIN + 20, MARGIN + 250, 10, BLACK);
  end;
end;

end.
