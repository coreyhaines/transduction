module Transduction
    exposing
        ( Reducer
        , Transducer
        , Stepper
        , reduce
        , reducer
        , transducer
        , compose
        , apply
        , map
        , statefulMap
        , take
        , withIndex
        )

{-| An Elm experiment in transducers. The purpose of transducers is to create composable elements which work on collections in powerful ways.
-}

import Transduction.Reply as Reply exposing (Reply)


{-| The `reduce` function needs a `Reducer`. This is a triple of:
-}
type Reducer state result input
    = Reducer (Reply state) (input -> state -> Reply state) (state -> result)


{-| The titular data structure is just a function which wraps itself around a `Reducer`. Transducers compose like normal functions using `(<<)` and `(>>)`. Note that the direction of the arrows is the **opposite** of the flow of collection values.

A `Transducer` will eventually be wrapped around a `Reducer`, so we need to know types for both 'ends' of the transducer.

-}
type Transducer transducerState reducerState transducerResult reducerResult transducerInput reducerInput
    = Transducer
        (Reducer reducerState reducerResult reducerInput
         -> Reducer transducerState transducerResult transducerInput
        )


{-| A stepper is a function which applies the step function successively to each element of the collection. This could be trivially implemented using `foldl`, but this gives the flexibility of implementing early termination based on the `Reply`.
-}
type alias Stepper state collection a =
    (a -> state -> Reply state) -> Reply state -> collection -> Reply state


{-| Where the magic happens. Takes a `Stepper` and a `Reducer` to make a function which reduces the collection.
-}
reduce : Stepper state collection a -> Reducer state result a -> collection -> result
reduce stepper (Reducer init step finish) collection =
    stepper step init collection |> Reply.state |> finish


{-| Make your own `Transducer`. Takes three functions.

  - The first transforms a reducer's initial value.
  - The second transforms a reducer's step function.
  - The third transforms a reducer's finish function.

-}
transducer :
    (Reply reducerState -> Reply transducerState)
    -> ((reducerInput -> reducerState -> Reply reducerState) -> transducerInput -> transducerState -> Reply transducerState)
    -> ((reducerState -> reducerResult) -> transducerState -> transducerResult)
    -> Transducer transducerState reducerState transducerResult reducerResult transducerInput reducerInput
transducer initF stepF finishF =
    Transducer (\(Reducer init step finish) -> reducer (initF init) (stepF step) (finishF finish))


{-| Make your own `Reducer`. Composed of:

  - Initial `Reply` state (can be `Halt` to stop before you begin).
  - A step function which updates the state based on an element from the collection.
  - A final clean-up step.

-}
reducer : Reply state -> (input -> state -> Reply state) -> (state -> result) -> Reducer state result input
reducer =
    Reducer


{-| If you have two transducers you can merge them into one.
-}
compose :
    Transducer transducerState intermediateState transducerResult intermediateResult a b
    -> Transducer intermediateState reducerState intermediateResult reducerResult b c
    -> Transducer transducerState reducerState transducerResult reducerResult a c
compose (Transducer transducer1) (Transducer transducer2) =
    Transducer (transducer1 << transducer2)


{-| Eventually your `Transducer` needs to have a base `Reducer` turning it into a `Reducer` of its own.
-}
apply :
    Transducer transducerState reducerState transducerResult reducerResult a b
    -> Reducer reducerState reducerResult b
    -> Reducer transducerState transducerResult a
apply (Transducer transducer) reducer =
    transducer reducer


map : (a -> b) -> Transducer state state result result a b
map f =
    transducer identity ((>>) f) identity


statefulMap :
    transducerState
    -> (a -> transducerState -> Result transducerState ( b, transducerState ))
    -> Transducer ( transducerState, reducerState ) reducerState result result a b
statefulMap init1 step1 =
    transducer
        (\init2 -> Reply.map ((,) init1) init2)
        (\step2 ->
            (\x ( state1, state2 ) ->
                case step1 x state1 of
                    Err newState1 ->
                        Reply.halt ( newState1, state2 )

                    Ok ( newX, newState1 ) ->
                        Reply.map ((,) newState1) (step2 newX state2)
            )
        )
        ((>>) Tuple.second)


withIndex : Transducer ( Int, state ) state result result a ( Int, a )
withIndex =
    statefulMap 0 (\x n -> Ok ( ( n, x ), n + 1 ))


take : Int -> Transducer ( Int, state ) state result result a a
take n =
    transducer
        (\init ->
            Reply.andThen
                (\state ->
                    if n <= 0 then
                        Reply.halt ( n, state )
                    else
                        Reply.continue ( n, state )
                )
                init
        )
        (\step x ( m, state ) ->
            Reply.andThen
                (\newState ->
                    if m <= 1 then
                        Reply.halt ( m - 1, newState )
                    else
                        Reply.continue ( m - 1, newState )
                )
                (step x state)
        )
        ((>>) Tuple.second)



-- withCount : Transducer ( Int, state ) state ( Int, result ) result a a
-- withCount (Reducer init step finish) =
--     Reducer
--         (Reply.map ((,) 0) init)
--         (\x ( n, state ) -> Reply.map ((,) (n + 1)) (step n state))
--         (\( n, state ) -> ( n, finish state ))
-- andThen : Stepper state collection b -> state -> Transducer state state result result collection b
-- andThen stepper init =
