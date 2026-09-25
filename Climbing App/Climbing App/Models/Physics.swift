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
    /// formula. This is what leads on the screen.
    ///
    /// Two sentences at most, and short ones. It used to run to five or six,
    /// which made a page of findings a page of essays: everything that is not
    /// the first two sentences is underneath, behind a control that says what
    /// it holds, and nobody has to read any of it to act on the finding.
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
                plain: "A bent arm is your bicep holding you up. A straight one hangs off bone, and bone does not get tired.",
                concept: "Muscular against skeletal support",
                law: "Elbow torque = load × distance from the joint to the line of the load",
                why: "A bent arm holds you up with your biceps. A straight one passes the load down the bone into your shoulder, and the torque your muscles have to supply falls towards zero as the elbow opens. Holding a bent arm is also isometric: above roughly half your maximum contraction, blood flow through the muscle is largely cut off, so a bent arm is on a clock in a way a straight one is not.",
                measured: "The mean angle of your elbows in the frames where your center of mass was near still."
            )

        case .weightOnArms:
            return PhysicsNote(
                plain: "Your hips sat to one side of your feet. The further out they are, the harder your fingers pull just to stop you rotating off.",
                concept: "Moment about the base of support",
                law: "Torque pulling you off the wall = your weight × how far your center of mass sits sideways of your feet",
                why: "Your feet are the pivot. The further your hips hang off to one side of them, the larger the turning moment trying to swing you off the wall, and your fingers are what resist it. The relationship is linear, so halving that sideways distance halves what your hands are holding. This is the whole mechanical content of turning a hip in.",
                measured: "How far your center of mass sat to the side of the line of your feet, in torso lengths."
            )

        case .lurchy:
            return PhysicsNote(
                plain: "Starting and stopping spikes the force on a hold well above your bodyweight. That spike is what pops you off.",
                concept: "Jerk, the rate of change of acceleration",
                law: "Jerk is the third derivative of position. Smooth movement keeps it small",
                why: "Force on a hold follows your acceleration. If acceleration changes abruptly, force spikes well above your bodyweight for an instant, and that spike is what tears you off a small edge or rips a foot. A move made at constant acceleration asks the hold for far less at its worst moment than the same move made in a lurch, even though both cover the same distance in the same time.",
                measured: "Log dimensionless jerk over your center of mass path, normalized by how long the climb took and how far you traveled, so a slow climb is not flattered."
            )

        case .impreciseFeet:
            return PhysicsNote(
                plain: "A foot only grips while you press on it. Every time you lift one to fix it, that weight goes back to your arms.",
                concept: "Friction and the normal force",
                law: "Friction available at a foothold is at most μ × the force you press into it",
                why: "Rubber grips in proportion to how hard it is pressed into the hold. Every time you lift a foot to adjust it, that normal force goes to zero and the load transfers to your hands until the foot is back. Two adjustments on one foothold means two spells of hanging off your arms that a single accurate placement would have avoided.",
                measured: "The number of times a foot moved again after it had already been placed."
            )

        case .hesitation:
            return PhysicsNote(
                plain: "Hanging still is not resting. Your forearms run down while you grip, whether you are moving or not.",
                concept: "Time under tension",
                law: "Grip capacity decays with the time you spend holding, not the distance you cover",
                why: "Standing still on a wall is not rest. Forearm force capacity falls away steadily while you are gripping, and above about half your maximum the muscle's own pressure closes off its blood supply, so it is working without resupply. Seconds spent hanging on a hold reading the next move are seconds subtracted from what you will have at the crux.",
                measured: "How many times your center of mass stopped, and for how long in total."
            )

        case .wandering:
            return PhysicsNote(
                plain: "Between any two positions there is a shortest way. Travel beyond it is work you do and then undo.",
                concept: "Directness between positions",
                law: "Waste = (what you travelled, minus the straight line from each position to the next) over what you travelled",
                why: "This is not measured against a straight line up the wall, because a boulder does not offer one: the holds are where the setter put them, and a climber who followed a diagonal problem perfectly would score badly against a vertical. It is measured against the straight line from each position you were in to the next one, and unlike a line up the middle of the wall that one is reachable, because both of its ends are places you actually were. Going further than it is a detour you took rather than a shape the route forced on you: a reach that set off and corrected, a swing hauled back in, a drift past a hold. Every one of those raises your mass and then lowers it again, or moves it sideways and back, and none of it gets you up the route.",
                measured: "The climb split into moves at the moments you were slowest, then, for each one, how far your center of mass travelled against the straight line between its two ends."
            )

        case .mistimedDynamics:
            return PhysicsNote(
                plain: "At the top of a throw you are briefly weightless. Catch the hold there and it barely has to hold you.",
                concept: "The deadpoint",
                law: "At the apex of the arc, vertical velocity passes through zero",
                why: "Throw for a hold and your body follows an arc. At the very top of that arc you are momentarily not moving up or down. Catch the hold there and it only has to hold you. Catch early and it has to stop you still traveling upward; catch late and it has to arrest a fall that has already begun. Both cost force the perfectly timed catch does not.",
                measured: "The signed time between your hand reaching the hold and the apex of your center of mass arc. Negative is early, positive is late."
            )

        case .unopposed:
            return PhysicsNote(
                plain: "Friction only exists while something presses into the hold. With your weight outside all your hands and feet, nothing presses back, so you swing.",
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
        plain: "How much your path doubled back on itself, against the ground it actually covered.",
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
