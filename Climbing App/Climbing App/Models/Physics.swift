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
                concept: "Muscular against skeletal support",
                law: "Elbow torque = load × distance from the joint to the line of the load",
                why: "A bent arm holds you up with your biceps. A straight one passes the load down the bone into your shoulder, and the torque your muscles have to supply falls towards zero as the elbow opens. Holding a bent arm is also isometric: above roughly half your maximum contraction, blood flow through the muscle is largely cut off, so a bent arm is on a clock in a way a straight one is not.",
                measured: "The mean angle of your elbows in the frames where your centre of mass was near still."
            )

        case .weightOnArms:
            return PhysicsNote(
                concept: "Moment about the base of support",
                law: "Torque pulling you off the wall = your weight × how far your centre of mass sits sideways of your feet",
                why: "Your feet are the pivot. The further your hips hang off to one side of them, the larger the turning moment trying to swing you off the wall, and your fingers are what resist it. The relationship is linear, so halving that sideways distance halves what your hands are holding. This is the whole mechanical content of turning a hip in.",
                measured: "How far your centre of mass sat to the side of the line of your feet, in torso lengths."
            )

        case .lurchy:
            return PhysicsNote(
                concept: "Jerk, the rate of change of acceleration",
                law: "Jerk is the third derivative of position. Smooth movement keeps it small",
                why: "Force on a hold follows your acceleration. If acceleration changes abruptly, force spikes well above your bodyweight for an instant, and that spike is what tears you off a small edge or rips a foot. A move made at constant acceleration asks the hold for far less at its worst moment than the same move made in a lurch, even though both cover the same distance in the same time.",
                measured: "Log dimensionless jerk over your centre of mass path, normalised by how long the climb took and how far you travelled, so a slow climb is not flattered."
            )

        case .impreciseFeet:
            return PhysicsNote(
                concept: "Friction and the normal force",
                law: "Friction available at a foothold is at most μ × the force you press into it",
                why: "Rubber grips in proportion to how hard it is pressed into the hold. Every time you lift a foot to adjust it, that normal force goes to zero and the load transfers to your hands until the foot is back. Two adjustments on one foothold means two spells of hanging off your arms that a single accurate placement would have avoided.",
                measured: "The number of times a foot moved again after it had already been placed."
            )

        case .hesitation:
            return PhysicsNote(
                concept: "Time under tension",
                law: "Grip capacity decays with the time you spend holding, not the distance you cover",
                why: "Standing still on a wall is not rest. Forearm force capacity falls away steadily while you are gripping, and above about half your maximum the muscle's own pressure closes off its blood supply, so it is working without resupply. Seconds spent hanging on a hold reading the next move are seconds subtracted from what you will have at the crux.",
                measured: "How many times your centre of mass stopped, and for how long in total."
            )

        case .wandering:
            return PhysicsNote(
                concept: "Geometric entropy",
                law: "H = ln(2L / C), where L is the path your centre of mass travelled and C is the perimeter of its convex hull",
                why: "Raising your mass by a given height costs the same work whatever route you take to get there. Horizontal excursions are different: every sideways metre is work you do and then undo, and none of it moves you up. Geometric entropy is the established measure of this in climbing research. A dead straight line scores zero and the number climbs as the path meanders.",
                measured: "The entropy of the path your centre of mass traced through the climb."
            )

        case .mistimedDynamics:
            return PhysicsNote(
                concept: "The deadpoint",
                law: "At the apex of the arc, vertical velocity passes through zero",
                why: "Throw for a hold and your body follows an arc. At the very top of that arc you are momentarily not moving up or down. Catch the hold there and it only has to hold you. Catch early and it has to stop you still travelling upward; catch late and it has to arrest a fall that has already begun. Both cost force the perfectly timed catch does not.",
                measured: "The signed time between your hand reaching the hold and the apex of your centre of mass arc. Negative is early, positive is late."
            )
        }
    }
}

// MARK: - The standing measurements

/// Notes for the numbers the card shows whether or not anything was flagged.
enum MetricNote {
    static let entropy = PhysicsNote(
        concept: "Geometric entropy",
        law: "H = ln(2L / C)",
        why: "How much your centre of mass wandered relative to the ground it actually covered. Zero is a straight line. It rises with every excursion that has to be undone.",
        measured: "Path length against the perimeter of the path's convex hull."
    )

    static let jerk = PhysicsNote(
        concept: "Log dimensionless jerk",
        law: "The third derivative of position, normalised by duration and path length",
        why: "How smoothly the movement was made. Lower means force on your holds stayed close to steady. Higher means it spiked.",
        measured: "The jerk of your centre of mass path across the whole climb."
    )

    static let elbow = PhysicsNote(
        concept: "Static elbow angle",
        law: "180 degrees is a straight arm",
        why: "How straight your arms were in the moments you were not moving, which is when a bent arm is pure cost.",
        measured: "Mean elbow angle across the frames where your centre of mass was near still."
    )
}
