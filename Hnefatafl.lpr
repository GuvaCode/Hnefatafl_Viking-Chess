program Hnefatafl;

uses
  Raylib, hnefatafl_game;

var
  GameState: TGameState;


begin
  InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, 'Hnefatafl - Viking Chess');
  SetTargetFPS(60);
 GameState := Default(TGameState);
 // Font := GetFontDefault();
  InitializeGame(GameState);

  while not WindowShouldClose() do
  begin
    UpdateGame(GameState);

    if not GameState.Animation.Active then
      HandleInput(GameState);

    BeginDrawing();
      ClearBackground(RAYWHITE);
      DrawBoard(GameState);
      DrawUI(GameState);
    EndDrawing();
  end;

  CloseWindow();
end.
