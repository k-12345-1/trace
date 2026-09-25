import Foundation

/// Why a leak costs you something.
///
/// Every finding Trace reports is a measurement, and every measurement is
/// standing on a piece of mechanics. Saying "your arms were bent" is a
/// complaint. Saying that a bent elbow needs muscle torque proportional to how
/// far the joint sits off the line of the load, and that a straight one passes
/// that load into bone, is a reason to change something.
///
/// The claims here are deliberately modest. Each one is a statement about
/// forces, not about what your beta should have been.
struct PhysicsNote {
    /// The thing itself, in words anyone can read, with no term of art and no
    /// formula. This is what leads on the screen. The rest is underneath it for
    /// anyone who wants to know why it is true, and nobody has to read it to
    /// act on the finding.
    let plain: String
    /// The named idea.
    let concept: String
    /// The relationship in one line, with a formula where there honestly is one.
    let law: String
    /// Why it costs energy on a wall.
    let why: String
    /// What Trace actually measured to say this, so the number is not a mystery.
    let measured: String
}

extension LeakKind {
    var physics: PhysicsNote {
        switch self {

        case .bentArms:
            return PhysicsNote(
                plain: "A bent arm is your bicep holding you up. A straight one hangs off your skeleton, and bone does not get tired. Straightening your arms whenever you are not actually moving is the cheapest thing you can change about your climbing.",
                concept: "Muscular against skeletal support",
                law: "Elbow torque = load × distance from the joint to the line of the load",
                why: "A bent arm holds you up with your biceps. A straight one passes the load down the bone into your shoulder, and the torque your muscles have to supply falls towards zero as the elbow opens. Holding a bent arm is also isometric: above roughly half your maximum contraction, blood flow through the muscle is largely cut off, so a bent arm is on a clock in a way a straight one is not.",
                measured: "The mean angle of your elbows in the frames where your center of mass was near still."
            )

        case .weightOnArms:
            return PhysicsNote(
                plain: "Your feet are the hinge you swing around. The further your hips drift to one side of them, the harder your fingers have to pull just to stop you rotating off. Turning a hip into the wall brings your weight back over your feet, and your hands get an easier job.",
                concept: "Moment about the base of support",
                law: "Torque pulling you off the wall = your weight × how far your center of mass sits sideways of your feet",
                why: "Your feet are the pivot. The further your hips hang off to one side of them, the larger the turning moment trying to swing you off the wall, and your fingers are what resist it. The relationship is linear, so halving that sideways distance halves what your hands are holding. This is the whole mechanical content of turning a hip in.",
                measured: "How far your center of mass sat to the side of the line of your feet, in torso lengths."
            )

        case .lurchy:
            return PhysicsNote(
                plain: "Starting and stopping spikes the force on a hold far above your own bodyweight for a moment. That spike is what pops you off a small edge. Moving at one steady speed asks the hold for much less, even though you get there just as fast.",
                concept: "Jerk, the rate of change of acceleration",
                law: "Jerk is the third derivative of position. Smooth movement keeps it small",
                why: "Force on a hold follows your acceleration. If acceleration changes abruptly, force spikes well above your bodyweight for an instant, and that spike is what tears you off a small edge or rips a foot. A move made at constant acceleration asks the hold for far less at its worst moment than the same move made in a lurch, even though both cover the same distance in the same time.",
                measured: "Log dimensionless jerk over your center of mass path, normalized by how long the climb took and how far you traveled, so a slow climb is not flattered."
            )

        case .impreciseFeet:
            return PhysicsNote(
                plain: "A foot only grips while you are pressing on it. Every time you pick it up to fix it, all that weight goes back to your arms until it lands again. Looking at the foot until it touches, and then leaving it, is the whole skill.",
                concept: "Friction and the normal force",
                law: "Friction available at a foothold is at most μ × the force you press into it",
                why: "Rubber grips in proportion to how hard it is pressed into the hold. Every time you lift a foot to adjust it, that normal force goes to zero and the load transfers to your hands until the foot is back. Two adjustments on one foothold means two spells of hanging off your arms that a single accurate placement would have avoided.",
                measured: "The number of times a foot moved again after it had already been placed."
            )

        case .hesitation:
            return PhysicsNote(
                plain: "Hanging still on a wall is not resting. Your forearms run down while you grip, whether you are moving or not, and above about half effort they even cut off their own blood supply. Time spent working out the next move while hanging is time taken off your best attempt at it.",
                concept: "Time under tension",
                law: "Grip capacity decays with the time you spend holding, not the distance you cover",
                why: "Standing still on a wall is not rest. Forearm force capacity falls away steadily while you are gripping, and above about half your maximum the muscle's own pressure closes off its blood supply, so it is working without resupply. Seconds spent hanging on a hold reading the next move are seconds subtracted from what you will have at the crux.",
                measured: "How many times your center of mass stopped, and for how long in total."
            )

        case .wandering:
            return PhysicsNote(
                plain: "Going up costs the same however you get there, but sideways does not: every meter across is work you do and then undo. A line that meanders costs you real energy for no height.",
                concept: "Geometric entropy",
                law: "H = ln(2L / C), where L is the path your center of mass traveled and C is the perimeter of its convex hull",
                why: "Raising your mass by a given height costs the same work whatever route you take to get there. Horizontal excursions are different: every sideways meter is work you do and then undo, and none of it moves you up. Geometric entropy is the established measure of this in climbing research. A dead straight line scores zero and the number climbs as the path meanders.",
                measured: "The entropy of the path your center of mass traced through the climb."
            )

        case .mistimedDynamics:
            return PhysicsNote(
                plain: "Throw for a hold and you follow an arc, and at the very top of that arc you are briefly weightless. Catch it there and the hold barely has to hold you. Catch it early or late and you are fighting your own momentum.",
                concept: "The deadpoint",
                law: "At the apex of the arc, vertical velocity passes through zero",
                why: "Throw for a hold and your body follows an arc. At the very top of that arc you are momentarily not moving up or down. Catch the hold there and it only has to hold you. Catch early and it has to stop you still traveling upward; catch late and it has to arrest a fall that has already begun. Both cost force the perfectly timed catch does not.",
                measured: "The signed time between your hand reaching the hold and the apex of your center of mass arc. Negative is early, positive is late."
            )

        case .unopposed:
            return PhysicsNote(
                plain: "Holds do not grip you, friction does, and friction only exists while something is pressing into the hold. Hang straight below a hold and gravity presses for you. Push two holds toward each other, like squeezing a box, and you make that press yourself, which is why compression problems work on holds you could never just hang off. When your weight ends up outside all of your hands and feet, there is nothing pushing back on the other side and you swing.",
                concept: "Friction, and the force pairs that make it",
                law: "f = μN. The friction a hold can give you is the coefficient of your skin or rubber against it, times the force pressing into it",
                why: "A hold does not hold you; friction does, and friction is bought with normal force. There are only two ways to make normal force. Gravity can do it, when you hang below a hold and your weight presses in. Or you can make it yourself, by loading two contacts toward each other so their sideways forces cancel: a pinch, a gaston against a sidepull, a hand pulling in while a foot pushes out. That cancelling pair is what makes a compression problem climbable on holds that would hold nothing at all if you simply hung off them. The same arithmetic explains where friction goes when it goes: only the part of your pull along the hold's normal counts, so pulling at an angle off that line gives N = F cos α. Thirty degrees off costs you thirteen percent of your friction and sixty degrees costs half, with nothing about the hold having changed. And when your center of mass hangs outside all of your contacts there is no second force at all: the sideways component has nothing to cancel it, so it becomes rotation about the outermost hand, which your fingers then pay for.",
                measured: "The time your center of mass spent horizontally outside the span of your hands and feet, against the time it spent between them. Trace measures this in the plane of the wall. It has no depth, so it cannot see which way a hold faces or how far your hips were off the wall, and it therefore never claims to know α."
            )
        }
    }
}

// MARK: - The standing measurements

/// Notes for the numbers the card shows whether or not anything was flagged.
enum MetricNote {
    static let entropy = PhysicsNote(
        plain: "How much you wandered on the way up. A straight line scores zero; every detour you had to undo pushes it higher.",
        concept: "Geometric entropy",
        law: "H = ln(2L / C)",
        why: "How much your center of mass wandered relative to the ground it actually covered. Zero is a straight line. It rises with every excursion that has to be undone.",
        measured: "Path length against the perimeter of the path's convex hull."
    )

    static let jerk = PhysicsNote(
        plain: "How evenly you moved. Lower means the force on your holds stayed steady, higher means it spiked.",
        concept: "Log dimensionless jerk",
        law: "The third derivative of position, normalized by duration and path length",
        why: "How smoothly the movement was made. Lower means force on your holds stayed close to steady. Higher means it spiked.",
        measured: "The jerk of your center of mass path across the whole climb."
    )

    static let elbow = PhysicsNote(
        plain: "How straight your arms were in the moments you were not moving. 180 is straight, and straight is free.",
        concept: "Static elbow angle",
        law: "180 degrees is a straight arm",
        why: "How straight your arms were in the moments you were not moving, which is when a bent arm is pure cost.",
        measured: "Mean elbow angle across the frames where your center of mass was near still."
    )
}
