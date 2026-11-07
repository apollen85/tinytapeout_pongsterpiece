<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Pongsterpiece - a basic **pong** game - a real ma**sterpiece**.

You know how it works - input pins for the paddles are listed in the project.

Adjust difficulty - increase ball or paddle speed by pulling the corresponding pin high.

### Hit boxes

Each paddle has 8 vertical zones. The resulting x velocity of the ball after a bounce increases as you get closer to the center of the paddle - and so do your chances of beating your opponent.

## How to test

1. Find a friend
2. Play pong
3. Beat your friend
4. Find a new friend
5. Repeat

Illustrated in python:

```python
while True:
    friend = get_friend()
    result = pong(self, friend)
    assert result = "You won" # Stop program if your friend wins
    # Friend goes out of scope here
```

### Serious instructions:

Connect momentary switches/buttons to the paddle pins and switches to the others. Configure speeds with some switches (HIGH values mean higher speeds) and play/pause the game with one switch. While the game is running, use the switches to move paddles up/down. Catch the ball so that it bounces to the other player.

## External hardware

VGA display, momentary push buttons for paddle movement, switches for play/pause and speed configuration.
