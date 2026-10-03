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
    /// Two short sentences at most, and one where one will do. It used to run
    /// to five or six, which made a page of findings a page of essays. What is
    /// not here sits underneath, behind a control that says what it holds, and
    /// nobody has to read any of it to act on the finding.
    let plain: String
    /// The named idea.
    let concept: String
    /// The relationship in one line, with a formula where there honestly is one.
    let law: String
    /// Why it costs energy on a wall, in two sentences. Longer than that and
    /// nobody opens it twice.
    let why: String
    /// What Trace actually measured to say this, so the number is not a mystery.
    let measured: String
}

extension LeakKind {
    var physics: PhysicsNote {
        switch self {

        case .bentArms:
            return PhysicsNote(
                plain: "Bent arms are your biceps holding you up. Straight ones hang off bone.",
                concept: "Muscular against skeletal support",
                law: "Elbow torque = load × distance from the joint to the line of the load",
                why: "Open the elbow and the load passes down the bone into your shoulder instead of through the muscle. A bent arm is also on a clock: held hard, it closes off its own blood supply.",
                measured: "Your mean elbow angle in the frames where you were near still."
            )

        case .weightOnArms:
            return PhysicsNote(
                plain: "Your hips hung to one side of your feet, and your fingers held the difference.",
                concept: "Moment about the base of support",
                law: "Torque pulling you off the wall = your weight × how far your center of mass sits sideways of your feet",
                why: "Your feet are the pivot, so the further your hips sit off to one side of them the harder the wall tries to swing you off. It is linear: halve that distance and you halve what your hands hold.",
                measured: "How far your center of mass sat sideways of your feet, in torso lengths."
            )

        case .lurchy:
            return PhysicsNote(
                plain: "Starting and stopping spikes the force on a hold well past your bodyweight.",
                concept: "Jerk, the rate of change of acceleration",
                law: "Jerk is the third derivative of position. Smooth movement keeps it small",
                why: "Force follows acceleration, so a sudden change asks the hold for far more than your weight for an instant. That instant is what rips a foot or tears you off a small edge.",
                measured: "The jerk of your path, normalized so a slow climb is not flattered."
            )

        case .impreciseFeet:
            return PhysicsNote(
                plain: "A foot grips only while you press on it. Every fix hands your arms the weight.",
                concept: "Friction and the normal force",
                law: "Friction available at a foothold is at most μ × the force you press into it",
                why: "Rubber grips in proportion to how hard it is pressed in, so lifting a foot to adjust it drops that force to nothing. Your hands carry you until it is back down.",
                measured: "How many times a foot moved again after it had been placed."
            )

        case .hesitation:
            return PhysicsNote(
                plain: "Hanging still is not resting. Your forearms run down while you grip.",
                concept: "Time under tension",
                law: "Grip capacity decays with the time you spend holding, not the distance you cover",
                why: "Grip fades with time spent holding, not ground covered, and above about half your maximum the muscle closes off its own blood supply. Seconds spent reading the next move come out of what you have at the crux.",
                measured: "How many times you stopped, and for how long in total."
            )

        case .wandering:
            return PhysicsNote(
                plain: "Between one position and the next there is a shortest way. You went further.",
                concept: "Directness between positions",
                law: "Waste = (what you travelled, minus the straight line from each position to the next) over what you travelled",
                why: "Not against a line up the wall, which no boulder offers, but against the straight line from each position you were in to the next. Anything past that is a detour you took rather than a shape the route forced on you: a reach that corrected, a swing hauled back, a drift past a hold.",
                measured: "Your travel between each pair of positions, against the straight line joining them."
            )

        case .mistimedDynamics:
            return PhysicsNote(
                plain: "At the top of a throw you are briefly weightless. Catch the hold there.",
                concept: "The deadpoint",
                law: "At the apex of the arc, vertical velocity passes through zero",
                why: "Your body follows an arc, and at the top of it you are neither rising nor falling, so the hold only has to hold you. Catch early and it stops you still rising; catch late and it arrests a fall.",
                measured: "The time between your hand reaching the hold and the apex of your arc."
            )

        case .overReaching:
            return PhysicsNote(
                plain: "A hand can only go as far as the arm is long. A foot moved first moves the whole body.",
                concept: "Reach as body travel plus arm extension",
                law: "Hand travel = shoulder travel along the reach + arm extension",
                why: "Extending the arm costs the shoulder and the fingers, and it is capped at one arm's length. Raising a foot lifts the shoulder with the legs, which are stronger and not on a clock, and leaves the arm to finish rather than to do it all.",
                measured: "On each upward reach, how far the shoulder travelled along the hand's direction, and whether either foot had landed somewhere new in the second and a half before."
            )

        case .squareHips:
            return PhysicsNote(
                plain: "Square hips push your weight away from the wall. A turned hip brings the shoulder in and the arm goes long.",
                concept: "Moment about the feet, and the reach a turned hip buys",
                law: "Torque off the wall = weight × the distance your hips sit out from your feet",
                why: "With the hips square the centre of mass sits out from the wall and the arm has to bend to hold it in. Turning a hip in puts the mass over the feet and brings the reaching shoulder closer to the hold, so the same hold is caught with a straighter arm.",
                measured: "Hip width at launch against your own widest, and the elbow angle of the reaching arm at the catch."
            )

        case .lockOffHeld:
            return PhysicsNote(
                plain: "A lock-off is a muscle holding a joint shut. Held, it closes its own blood supply.",
                concept: "Isometric contraction and occlusion",
                law: "Elbow torque = load × distance from the joint to the line of the load, for as long as it is held",
                why: "Moving through a lock-off costs an instant. Holding one costs the whole time, and a forearm contracting hard shuts off its own circulation, so the pump arrives while you are standing still. It also loads the elbow tendons in the position that injures them.",
                measured: "The longest stretch a bent arm stayed still on its hold."
            )

        case .elbowsFlared:
            return PhysicsNote(
                plain: "An elbow up and out hangs the load on the shoulder joint instead of the back.",
                concept: "Line of force through the shoulder",
                law: "The further the elbow sits from the line between hand and torso, the more of the load the shoulder holds as torque",
                why: "With the elbow tucked and the shoulder blade set, the pull runs into the big muscles of the back. Flared, the same pull goes through the rotator cuff and the inner elbow, which is where climbers get hurt.",
                measured: "Seconds an elbow sat above its shoulder while the hand was below it, on a hand that was not moving."
            )

        case .hipsBehind:
            return PhysicsNote(
                plain: "A reach is measured from the hips, not the shoulder.",
                concept: "Reach as the sum of hips, torso and arm",
                law: "The hand reaches as far as the shoulder, and the shoulder goes where the hips go",
                why: "An arm is a fixed length. What changes how far a hold is from the hand is where the shoulder starts, and the shoulder starts above the hips. Hips moved across first bring the shoulder half a torso closer before the arm does anything; left behind, the arm makes up the whole distance and arrives bent.",
                measured: "Where the hips sat against the other hand as each reach across set off, and whether they moved toward the hold while the arm went."
            )

        case .highStep:
            return PhysicsNote(
                plain: "A foot near hip height is a foot you cannot stand up on without hauling.",
                concept: "Mechanical advantage of the leg",
                law: "The higher the foot relative to the hips, the more the knee is folded and the less force the leg can give",
                why: "A deeply bent knee is weak, and the hips end up far from the foot, so the arms have to do the lifting a leg was meant to. Two smaller steps keep the knee in its strong range and the hips over the foot.",
                measured: "Where each foot landed, against the other foot and against the hips."
            )

        case .unopposed:
            return PhysicsNote(
                plain: "Friction needs something pressing into the hold. Outside your hands and feet, nothing is.",
                concept: "Friction, and the force pairs that make it",
                law: "f = μN. The friction a hold can give you is the coefficient of your skin or rubber against it, times the force pressing into it",
                why: "Friction is bought with normal force, and there are two ways to make it: hang below a hold so your weight presses in, or load two contacts toward each other so their sideways pulls cancel. Outside all of them nothing cancels, and the swing becomes rotation about your outermost hand.",
                measured: "The time your center of mass spent outside the span of your hands and feet. Trace sees the wall plane only, so it has no depth and never guesses which way a hold faces."
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
