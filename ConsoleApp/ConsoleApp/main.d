import std.algorithm, std.random, core.thread, consoled, std.ascii : isWhite;

void main(string[] argv)
{
	SnakeGame game = new SnakeGame();

	try
	{
		game.mainGameLoop();	
	}
	catch (Exception t)
	{
		writecln(t);
		while (KeyAvailable())
			ReadKey(false);

		ReadKey(false);
		ReadKey(false);
		ReadKey(false);
	}
}

enum Direction : char 
{ 
	Up = 'w', 
	Left = 'a', 
	Down = 's', 
	Right = 'd' 
}

enum GameObjectType : char 
{ 
	Empty = ' ',
	Wall = '#',
	Apple = '@',
	SnakeBody1 = 'o',
	SnakeBody2 = '*',
	SnakeBody3 = '+',
	SnakeHeadL = '<',
	SnakeHeadR = '>',
	SnakeHeadU = '^',
	SnakeHeadD = 'v'
}

pure Direction oppositeDirection(Direction dir)
{
	final switch(dir)
	{
		case Direction.Left: return Direction.Right;
		case Direction.Right: return Direction.Left;
		case Direction.Up: return Direction.Down;
		case Direction.Down: return Direction.Up;
	}
}

pure GameObjectType toSnakeHead(Direction dir)
{
	final switch(dir)
	{
		case Direction.Down:
			return GameObjectType.SnakeHeadD;
		case Direction.Up:
			return GameObjectType.SnakeHeadU;
		case Direction.Left:
			return GameObjectType.SnakeHeadL;
		case Direction.Right:
			return GameObjectType.SnakeHeadR;
	}
}

pure int getDeltaX(Direction dir)
{
	final switch (dir)
	{
		case Direction.Up: case Direction.Down:
			return 0;
		case Direction.Right:
			return 1;
		case Direction.Left:
			return -1;
	}
}

pure int getDeltaY(Direction dir)
{
	final switch (dir)
	{
		case Direction.Right: case Direction.Left:
			return 0;
		case Direction.Down:
			return 1;
		case Direction.Up:
			return -1;
	}
}

pure Vector2D getDelta(Direction dir)
{
	final switch (dir)
	{
		case Direction.Left:
			return Vector2D(-1, 0);
		case Direction.Right:
			return Vector2D(1, 0);
		case Direction.Up:
			return Vector2D(0, -1);
		case Direction.Down:
			return Vector2D(0, 1);
	}
}

struct Rect2D
{
	this(Vector2D origin_, uint width_, uint height_)
	{
		origin = origin_;
		width = width_;
		height = height_;
	}

	Vector2D origin;
	uint width;
	uint height;

	ConsolePoint bottomRight() const pure
	{
		return ConsolePoint(origin.x + width, origin.y + height);
	}

	alias origin o;
	alias width w;
	alias height h;
	alias bottomRight br;
}

struct Vector2D
{
	int x, y;

	pure this(int x_, int y_)
	{
		x = x_;
		y = y_;
	}

	Vector2D opBinary(string op)(Vector2D rhs) if (op == "+" || op =="-")
	{
		return Vector2D(mixin("x" ~op~ "rhs.x"),
						mixin("y" ~op~ "rhs.y"));
	}

	ref Vector2D opOpAssign(string op)(Vector2D rhs) if (op == "+" || op =="-")
	{
		mixin("x" ~op~ "=rhs.x");
		mixin("y" ~op~ "=rhs.y");

		return this;
	}
}

class GameObject
{
	char representation;
	Vector2D position;

	alias representation rep;

	this(char representation_, Vector2D position_)
	{
		this.rep = representation_;
		this.position = position_;
	}

	void draw(Rect2D gameArea) const
	{
		draw(gameArea, Color.white);
	}

	void draw(Rect2D gameArea, Color color) const
	{
		with (position) with (gameArea)
			setCursorPos(o.x + x, o.y + y);

		foreground = color;
		writecln(rep);
	}
}

class Snake
{
	GameObject[] snakeBody;
	Direction direction;
	Color color;
	bool isAlive;

	@property
	GameObject snakeHead() { return snakeBody[0]; }

	this() { this(Color.white); }

	this(Color color_)
	{
		isAlive = true;
		direction = Direction.Right;
		color = color_;
		snakeBody = [ new GameObject(GameObjectType.SnakeHeadR, Vector2D(4, 3)), ];
	}

	void takeInput(ConsoleKeyInfo info)
	{
		switch (info.Key)
		{
			case ConsoleKey.W: 
			case ConsoleKey.A: 
			case ConsoleKey.S: 
			case ConsoleKey.D:
				auto dir = cast(Direction)('a' + info.Key - ConsoleKey.A);
				if (dir.oppositeDirection == direction) break;
				direction = dir;
				snakeHead.rep = direction.toSnakeHead();
				break;
			default:
				break;
		}
	}

	static Vector2D handleOverflow(Vector2D snakeHeadPos, Rect2D gameArea) pure
	{
		if (snakeHeadPos.x < 0) snakeHeadPos.x = gameArea.w - 1;
		if (snakeHeadPos.y < 0) snakeHeadPos.y = gameArea.h - 1;

		if (snakeHeadPos.x >= gameArea.w) snakeHeadPos.x = 0;
		if (snakeHeadPos.y >= gameArea.h) snakeHeadPos.y = 0;

		return snakeHeadPos;
	}

	void move(Rect2D gameArea)
	{
		auto newHeadPos = snakeHead.position + getDelta(direction); //move 1 left, right, up or down, depending on current direction
		newHeadPos = handleOverflow(newHeadPos, gameArea);

		foreach(i, go; snakeBody)
		{
			swap(go.position, newHeadPos);

			if (i > 0 && go.position == snakeBody[0].position) //the snake has bitten itself!
			{ isAlive = false; return; }
		}

		with (gameArea)
		setCursorPos(o.x + newHeadPos.x, o.y + newHeadPos.y);

		writec(' ');
	}

	void grow()
	{
		string snakeName = "Penka ";

		GameObject newPart = 
			new GameObject(snakeName[(snakeBody.length - 1) % snakeName.length], 
						   snakeBody[$ -1].position);

		snakeBody ~= newPart;
	}

	void draw(Rect2D gameArea) const
	{
		foreach(go; snakeBody)
			go.draw(gameArea, color);
	}

	bool collideWith(Vector2D pos) const pure
	{
		return std.algorithm.any!(
			(go) => go.position == pos)
			(snakeBody);
	}
}

class SnakeGame
{
	Snake snake;
	GameObject apple;
	GameObject[] obstacles;
	Duration frameSleepTime;
	uint score;

	//All objects are located in the abstract game area space (from 0 to gameArea.w ot .h)
	//At draw time they are rendered at the actual screen position after the displacement is applied from gameArea.origin;
	Rect2D gameArea;	

	this()
	{
		//These two initializations should happen first
		gameArea = Rect2D(Vector2D(2, 3), 70, 30); 
		frameSleepTime = dur!"msecs"(120);

		snake = new Snake();
		apple = new GameObject(GameObjectType.Apple, getNewApplePosition());		
	}

	void mainGameLoop()
	{
		cursorVisible = false;
		while (snake.isAlive)
		{
			draw();	
			getInput();
			update();					
			Thread.sleep(frameSleepTime);
		}

		showScore();
	}

	void getInput()
	{
		ConsoleKeyInfo info;

		if (KeyAvailable()) 
		{
			info = ReadKey(false);

			snake.takeInput(info);
		}
	}	

	void update()
	{
		snake.move(gameArea);

		if (snake.snakeHead.position == apple.position)
		{
			score += 10;
			snake.grow();
			apple.position = getNewApplePosition();
			frameSleepTime -= dur!"msecs"(1);
		}

	}

	void draw() const
	{
		drawGameBorder();
		apple.draw(gameArea);
		snake.draw(gameArea);
	}

	void drawGameBorder() const
	{
		//top:
		foreground = Color.gray;
		consoled.drawBox(ConsolePoint(), 
						 ConsolePoint(consoled.width, gameArea.o.y - 1), '*');
		//left:
		consoled.fillArea(ConsolePoint(0, gameArea.o.y), 
						 ConsolePoint(gameArea.o.x, consoled.height - 2), '*');
		//right:
		consoled.fillArea(ConsolePoint(gameArea.br.x, gameArea.o.y), 
						  ConsolePoint(consoled.width, consoled.height - 2), '*');
		//bottom:
		consoled.fillArea(ConsolePoint(gameArea.o.x, gameArea.br.y), 
						  ConsolePoint(consoled.width, consoled.height - 2), '*');

		//Show score if space is available at the top of the screen
		if (gameArea.o.y > 2)
		{
			setCursorPos(consoled.width / 2 - 10, 1);
			writec(Fg.yellow, format("Score: %s", score));
		}
	}

	void showScore()
	{
		setCursorPos(0, 0);
		writecln(format("Game Over! Score: %s", score));
		ReadKey(false);
		//ReadKey(false); //For some reason one ReadKey() is not enough to pause the game before exit
	}

	Vector2D getNewApplePosition()
	{
		Vector2D newPos;

		do
			newPos = Vector2D(uniform(0, gameArea.w),
							  uniform(0, gameArea.h));
		while (collidesWithExistingObjects(newPos));

		return newPos;
	}

	pure bool collidesWithExistingObjects(Vector2D pos)
	{
		return snake.collideWith(pos);
	}
}
