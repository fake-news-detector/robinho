module TwitterGraph exposing (main)

{-| This demonstrates laying out the characters in Les Miserables
based on their co-occurence in a scene. Try dragging the nodes!
-}

import AnimationFrame
import Data.TweetsGraph exposing (..)
import Graph exposing (Edge, Graph, Node, NodeContext, NodeId)
import Html exposing (button, div)
import Html.Attributes exposing (attribute)
import Html.Events exposing (on, onClick, onMouseEnter, onMouseLeave)
import RemoteData exposing (..)
import Svg exposing (..)
import Svg.Attributes as Attr exposing (..)
import Time exposing (Time)
import Visualization.Force as Force exposing (State)


screenWidth : Float
screenWidth =
    600


screenHeight : Float
screenHeight =
    504


type Msg
    = Tick Time
    | LoadTweets
    | TweetsResponse (WebData (List Tweet))
    | MouseOver NodeId
    | MouseLeave NodeId


type alias Model =
    { tweetsData : WebData (List Tweet)
    , graph : Graph Entity ()
    , simulation : Force.State NodeId
    , highlightedNode : Maybe NodeId
    }


generateForces : Graph n e -> State Int
generateForces graph =
    let
        links =
            graph
                |> Graph.edges
                |> List.map (\{ from, to } -> { source = from, target = to, distance = 20, strength = Just 1.5 })
    in
    [ Force.customLinks 1 links
    , Force.manyBodyStrength -45 <| List.map .id <| Graph.nodes graph
    , Force.center (screenWidth / 2) (screenHeight / 2)
    ]
        |> Force.simulation
        |> Force.iterations 12


init : ( Model, Cmd Msg )
init =
    ( { tweetsData = NotAsked
      , graph = initialGraph
      , simulation = generateForces initialGraph
      , highlightedNode = Nothing
      }
    , Cmd.none
    )


updateContextWithValue : NodeContext Entity () -> Entity -> NodeContext Entity ()
updateContextWithValue nodeCtx value =
    let
        node =
            nodeCtx.node
    in
    { nodeCtx | node = { node | label = value } }


updateGraphWithList : Graph Entity () -> List Entity -> Graph Entity ()
updateGraphWithList =
    let
        graphUpdater value =
            Maybe.map (\ctx -> updateContextWithValue ctx value)
    in
    List.foldr (\node graph -> Graph.update node.id (graphUpdater node) graph)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg ({ graph, simulation } as model) =
    case msg of
        Tick t ->
            let
                ( newState, list ) =
                    Force.tick simulation <| List.map .label <| Graph.nodes graph
            in
            ( { model | graph = updateGraphWithList graph list, simulation = newState }, Cmd.none )

        LoadTweets ->
            ( { model | tweetsData = Loading }
            , getTweetData
                |> RemoteData.sendRequest
                |> Cmd.map TweetsResponse
            )

        TweetsResponse response ->
            let
                graph =
                    case response of
                        Success tweets ->
                            buildTweetsGraph tweets
                                |> mapContexts

                        _ ->
                            Debug.crash "fail"
            in
            ( { model
                | tweetsData = response
                , graph = graph
                , simulation = generateForces graph
              }
            , Cmd.none
            )

        MouseOver nodeId ->
            ( { model | highlightedNode = Just nodeId }, Cmd.none )

        MouseLeave nodeId ->
            ( { model | highlightedNode = Nothing }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    if Force.isCompleted model.simulation then
        Sub.none
    else
        AnimationFrame.times Tick


linkElement : Model -> { b | from : NodeId, to : NodeId } -> Svg msg
linkElement { graph } edge =
    let
        getEntity id =
            Graph.get id graph
                |> Maybe.map (.node >> .label)
                |> Maybe.withDefault (Force.entity 0 { id = "", screenName = "" })

        source =
            getEntity edge.from

        target =
            getEntity edge.to
    in
    line
        [ strokeWidth "1"
        , stroke "#aaa"
        , x1 (toString source.x)
        , y1 (toString source.y)
        , x2 (toString target.x)
        , y2 (toString target.y)
        ]
        []


nodeElement : Model -> { c | label : { b | x : Float, y : number, value : IdAndScreenName }, id : NodeId } -> Svg Msg
nodeElement { highlightedNode, graph } node =
    let
        connectionsCount =
            Graph.edges graph
                |> List.filter (\{ to } -> to == node.id)
                |> List.length

        nodeSize =
            (3 + toFloat connectionsCount * 0.2)
                |> Basics.min 10

        nodeText =
            Svg.text_
                [ x (toString <| node.label.x + nodeSize + 5)
                , y (toString <| node.label.y + 5)
                , Attr.style "font-family: sans-serif; font-size: 14px"
                ]
                [ text node.label.value.screenName ]

        nodeRect =
            rect
                [ x (toString <| node.label.x - 11)
                , y (toString <| node.label.y - 11)
                , width (toString <| String.length node.label.value.screenName * 11)
                , height (toString <| 22)
                , rx (toString 10)
                , ry (toString 10)
                , fill "#FFF"
                , stroke "#333"
                ]
                []

        nodeCircle =
            circle
                [ r (toString nodeSize)
                , fill "#FFF"
                , stroke "#000"
                , strokeWidth "1px"
                , cx (toString node.label.x)
                , cy (toString node.label.y)
                ]
                [ Svg.title [] [ text node.label.value.screenName ]
                ]
    in
    a
        [ onMouseEnter (MouseOver node.id)
        , onMouseLeave (MouseLeave node.id)
        , attribute "href" ("https://twitter.com/" ++ node.label.value.screenName ++ "/status/" ++ node.label.value.id)
        , target "_blank"
        ]
        (case ( highlightedNode == Just node.id, connectionsCount > 4 ) of
            ( True, _ ) ->
                [ nodeRect, nodeText, nodeCircle ]

            ( False, True ) ->
                [ nodeText, nodeCircle ]

            ( False, False ) ->
                [ nodeCircle ]
        )


view : Model -> Svg Msg
view model =
    div []
        [ svg
            [ width (toString screenWidth ++ "px"), height (toString screenHeight ++ "px") ]
            [ g [ class "links" ] <| List.map (linkElement model) <| Graph.edges model.graph
            , g [ class "nodes" ] <| List.map (nodeElement model) <| Graph.nodes model.graph
            ]
        , button [ onClick LoadTweets ] [ Html.text "Load data" ]
        ]


main : Program Never Model Msg
main =
    Html.program
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }