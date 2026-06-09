extends Area2D
@onready var animated_sprite = $AnimatedSprite2D
var speed = 250
var direction = Vector2.RIGHT

func _ready():

	animated_sprite.play("rift")

func _physics_process(delta):

	position += direction * speed * delta
